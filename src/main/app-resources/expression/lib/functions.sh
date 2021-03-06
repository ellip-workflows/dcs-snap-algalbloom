# define the exit codes

SUCCESS=0
ERR_NOINPUT=1
ERR_SNAP=2
ERR_NOPARAMS=5

# add a trap to exit gracefully
function cleanExit ()
{
   local retval=$?
   local msg=""
   case "${retval}" in
     ${SUCCESS})      msg="Processing successfully concluded";;
     ${ERR_NOPARAMS}) msg="Expression not defined";;
     ${ERR_SNAP})    msg="SNAP failed to process product ${product} (Java returned ${res}).";;
     *)             msg="Unknown error";;
   esac
   [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
   exit ${retval}
}
trap cleanExit EXIT

function set_env() {

  # create the output folder to store the output products
  mkdir -p ${TMPDIR}/output
  export OUTPUTDIR=${TMPDIR}/output

  # retrieve the parameters value from workflow or job default value
  expression="$( ciop-getparam expression )"

  # run a check on the expression value, it can't be empty
  [ -z "${expression}" ] && return ${ERR_NOPARAMS}

  export SNAP_HOME=/opt/snap
  export PATH=${SNAP_HOME}/bin:${PATH}
  export SNAP_VERSION=$( cat ${SNAP_HOME}/VERSION.txt )
}

function main() {

  local inputfile=$1

  # report activity in log
  ciop-log "INFO" "Retrieving ${inputfile} from storage"

  # retrieve the remote geotiff product to the local temporary folder
  enclosure="$( opensearch-client ${inputfile} enclosure )"
  retrieved=$( ciop-copy -o $TMPDIR ${enclosure} )

  # check if the file was retrieved
  [ "$?" == "0" -a -e "${retrieved}" ] || exit ${ERR_NOINPUT}

  # report activity
  ciop-log "INFO" "Retrieved $( basename $retrieved ), moving on to expression"
  outputname=$( basename $retrieved )

  SNAP_REQUEST=${TMPDIR}/snap_request.xml

  cat << EOF > ${SNAP_REQUEST}
<?xml version="1.0" encoding="UTF-8"?>
<graph>
  <version>1.0</version>
  <node id="1">
    <operator>Read</operator>
      <parameters>
        <file>${retrieved}</file>
      </parameters>
  </node>
  <node id="2">
    <operator>BandMaths</operator>
    <sources>
      <source>1</source>
    </sources>
    <parameters>
      <targetBands>
        <targetBand>
          <name>out</name>
          <expression>${expression}</expression>
          <description>Processed Band</description>
          <type>float32</type>
        </targetBand>
      </targetBands>
    </parameters>
  </node>
  <node id="write">
    <operator>Write</operator>
    <sources>
       <source>2</source>
    </sources>
    <parameters>
      <file>${OUTPUTDIR}/${outputname}</file>
   </parameters>
  </node>
</graph>
EOF

  gpt ${SNAP_REQUEST} || return ${ERR_SNAP}

  outputname=$( basename $retrieved)

    tar -C ${OUTPUTDIR} -czf ${TMPDIR}/${outputname}.tgz ${outputname}.dim ${outputname}.data

  ciop-log "INFO" "Publishing ${outputname}.tgz"
  ciop-publish ${TMPDIR}/${outputname}.tgz

  # cleanup
  rm -fr ${retrieved} ${OUTPUTDIR}/${outputname}.d* ${TMPDIR}/${outputname}.tgz

}
 
 
