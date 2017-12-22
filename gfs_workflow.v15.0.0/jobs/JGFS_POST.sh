#!/bin/ksh
set -x

#--------------------------------------------------------------------
#--Fanglin Yang, December 2016
#  Running NCEP Unified Post to process FV3GFS forecasts.
#  Rahul Mahajan, April 2017
#  Running NCEP Unified Post to process FV3GFS analysis.
#  Rahul Mahajan, December 2017
#  Running NCEP Unified Post to concurrently process FV3GFS forecasts
#--------------------------------------------------------------------

export CDATE=${CDATE:-"2016100300"}
export CDUMP=${CDUMP:-gfs}

# Forecast specific variables
export GG=${master_grid:-"0p25deg"}         # 1deg 0p5deg 0p25deg 0p125deg
export OUTPUT_GRID=${OUTPUT_GRID:-"latlon"} # input grid type, lat-lon or gaussian_grid

# Process analysis file only
export ANALYSIS_POST=${ANALYSIS_POST:-"NO"}

pwd=$(pwd)
export NWPROD=${NWPROD:-$pwd}
export COMROT=${COMROT:-$pwd}
export COMOUT=${COMOUT:-${COMROT:-$pwd}}
export BASEDIR=${BASEDIR:-$NWPROD}   # gfs_workflow.v15.0.0/para
export BASE_GSM=${BASE_GSM:-$NWPROD} # global_shared.v15.0.0

export ver=${ver:-"v15.0.0"}
export nemsioget=${nemsioget:-${NEMSIOGET:-$NWPROD/util/exec/nemsio_get}}
export HOMEglobal=${BASE_POST:-$NWPROD}
export EXECglobal=$HOMEglobal/exec
export USHglobal=$HOMEglobal/ush
export USHgfs=$HOMEglobal/ush
export PARMglobal=$HOMEglobal/parm
export FIXglobal=$BASE_GSM/fix
export NWROOTprod=$NWROOT
export ens=NO

export POSTGPEXEC=${POSTGPEXEC:-$HOMEglobal/exec/ncep_post}
export POSTGPSH=${POSTGPSH:-$HOMEglobal/ush/global_nceppost.sh}
export POSTGRB2TBL=${POSTGRB2TBL:-$NWPROD/lib/g2tmpl/v1.3.0/src/params_grib2_tbl_new}
export MODEL_OUT_FORM=${MODEL_OUT_FORM:-"binarynemsiompiio"}

export APRUN=${APRUN_NP:-${APRUN:-""}}

export GFSDOWNSH=${GFSDOWNSH:-$BASEDIR/ush/gfs_downstream_nems.sh}
export GFSDWNSH=${GFSDWNSH:-$BASEDIR/ush/gfs_dwn_nems.sh}
export PARM_SIB=${PARM_SIB:-$BASE_POST/parm}
export APRUN_DWN=${APRUN_DWN:-${APRUN:-""}}

####################################
# Specify RUN Name and model
####################################
export envir=${envir:-"prod"}
export NET=${NET:-"fv3"}
export RUN=${RUN:-${CDUMP:-gfs}}

# Set cycle time and date parameters
export PDY=$(echo $CDATE | cut -c1-8)
export cyc=$(echo $CDATE | cut -c9-10)
export TCYC=${TCYC:-".t${cyc}z."}
export SUFFIX=${SUFFIX:-".nemsio"}
export PREFIX=${PREFIX:-${RUN}${TCYC}}

####################################
# Specify Execution Areas
####################################

export DATA=${DATA:-${DATATMP:-${pwd}$$}}
export COMIN=$DATA
if [ ! -s $DATA ]; then mkdir -p $DATA ; fi
cd $DATA || exit 8
rm -f ${DATA}/*

####################################
# SENDSMS  - Flag Events on SMS
# SENDCOM  - Copy Files From TMPDIR to $COMOUT
# SENDDBN  - Issue DBNet Client Calls
# RERUN    - Rerun posts from beginning (default no)
# VERBOSE  - Specify Verbose Output in global_postgp.sh
####################################
export SAVEGES=NO
export SENDSMS=NO
export SENDCOM=YES
export SENDDBN=NO
export RERUN=NO
export VERBOSE=YES

####################################
# Specify Special Post Vars
####################################
export IGEN_ANL=81
export IGEN_FCST=96
export POSTGPVARS="KPO=47,PO=1000.,975.,950.,925.,900.,875.,850.,825.,800.,775.,750.,725.,700.,675.,650.,625.,600.,575.,550.,525.,500.,475.,450.,425.,400.,375.,350.,325.,300.,275.,250.,225.,200.,175.,150.,125.,100.,70.,50.,30.,20.,10.,7.,5.,3.,2.,1.,"

export OUTTYP=4
export GRIBVERSION=grib2

####################################
# Specify Timeout Behavior of Post
# SLEEP_TIME - Amount of time to wait for
#              a restart file before exiting
# SLEEP_INT  - Amount of time to wait between
#              checking for restart files
####################################
export SLEEP_TIME=900
export SLEEP_INT=5

#---------------------------------------------------
# work on analysis file
if [ $ANALYSIS_POST = "YES" ]; then

  export IGEN_GDAS_ANL=82
  export IDRT=4

  flist=${flist:-"$COMROT/${PREFIX}atmanl${SUFFIX}"}
  export post_times="anl"

  export restart_file=$COMROT/${PREFIX}atmanl${SUFFIX}
  ln -fs $COMROT/${PREFIX}atmanl${SUFFIX}  $COMIN/${PREFIX}atmanl${SUFFIX}
  ln -fs NULL                              $COMIN/${PREFIX}flxanl${SUFFIX}
  ln -fs NULL                              $COMIN/${PREFIX}sfcanl${SUFFIX}

  export NEMSINP=$COMIN/${PREFIX}atmanl${SUFFIX}
  export FLXINP=$COMIN/${PREFIX}flxanl${SUFFIX}
  export SFCINP=$COMIN/${PREFIX}sfcanl${SUFFIX}

  $HOMEglobal/scripts/exgfs_nceppost.sh.ecf
  rc1=$?
  echo $rc1

  #--rename master grib2 following parallel convention
  export PGBOUT2_ops=$COMOUT/${PREFIX}master.grb2anl
  export PGBOUT2_ops_idx=$COMOUT/${PREFIX}master.grb2ianl
  export PGBOUT2=$COMOUT/pgrbm${post_times}.${RUN}.${CDATE}.grib2
  export PGBOUT2_idx=$COMOUT/pgrbm${post_times}.${RUN}.${CDATE}.grib2.idx
  mv $PGBOUT2_ops $PGBOUT2
  mv $PGBOUT2_ops_idx $PGBOUT2_idx

  # call down-stream job
  if [ $GFS_DOWNSTREAM = "YES" ]; then
    export FH=-1
    $GFSDOWNSH
    rc2=$?
    echo $rc2
  fi

  [[ ${KEEPDATA:-NO} != YES ]] && rm -rf $DATA
  err=$rc2
  exit $err

fi
#---------------------------------------------------

#---------------------------------------------------
# Now work on forecast files

# Parameters dependent on OUTPUT_GRID
if [ $OUTPUT_GRID = "latlon" ]; then
   export IDRT=0
   if [ $CDUMP = "gdas" ]; then
      export IDRT=4
   fi
else
   export IDRT=4
fi

####################################
# Specify resolution dependent parameters
####################################
if [ $IDRT -eq 0 ] ; then
   # 0.125 deg
  if [ $GG = "0p125deg" ] ; then
    export LONB=2880
    export LATB=1440
  # 0.25 deg
  elif [ $GG = "0p25deg" ] ; then
    export LONB=1440
    export LATB=720
  # 0.5 deg
  elif [ $GG = "0p50deg" ] ; then
    export LONB=720
    export LATB=360
  fi
fi


#---------------------------------------------------
# Get a list of forecast files that are to be worked on
flist=${flist:-$(ls -1 $COMROT/${PREFIX}atmf???${SUFFIX})}

#---------------------------------------------------
# Loop over files
for fname in $flist; do

   fname=$(basename $fname)
   export post_times=$(echo $fname | cut -d. -f3 | cut -c5-)

   export restart_file=$COMROT/${PREFIX}atmf
   ln -fs $COMROT/${PREFIX}atmf${post_times}${SUFFIX} $COMIN/${PREFIX}atmf${post_times}${SUFFIX}
   if [ $CDUMP = "gfs" -a $QUILTING = ".false." ] ; then
      ln -fs $COMROT/${PREFIX}atmf${post_times}${SUFFIX} $COMIN/${PREFIX}flxf${post_times}${SUFFIX}
   else
      ln -fs $COMROT/${PREFIX}sfcf${post_times}${SUFFIX} $COMIN/${PREFIX}flxf${post_times}${SUFFIX}
   fi
   ln -fs $COMROT/${PREFIX}sfcf${post_times}${SUFFIX} $COMIN/${PREFIX}sfcf${post_times}${SUFFIX}

   export NEMSINP=$COMIN/${PREFIX}atmf${post_times}${SUFFIX}
   export FLXINP=$COMIN/${PREFIX}flxf${post_times}${SUFFIX}
   export SFCINP=$COMIN/${PREFIX}sfcf${post_times}${SUFFIX}

   $HOMEglobal/scripts/exgfs_nceppost.sh.ecf
   rc1=$?
   echo $rc1

   #--rename master grib2 following parallel convention
   export PGBOUT2_ops=$COMOUT/${PREFIX}master.grb2f${post_times}
   export PGBOUT2_ops_idx=$COMOUT/${PREFIX}master.grb2if${post_times}
   export PGBOUT2=$COMOUT/pgrbm${post_times}.${RUN}.${CDATE}.grib2
   export PGBOUT2_idx=$COMOUT/pgrbm${post_times}.${RUN}.${CDATE}.grib2.idx
   mv $PGBOUT2_ops $PGBOUT2
   mv $PGBOUT2_ops_idx $PGBOUT2_idx

   export FH=`expr $post_times + 0`
   if [ $FH -lt 10 ]; then export FH=0$FH; fi

   # call down-stream jobs
   if [ $GFS_DOWNSTREAM = "YES" ]; then
      $GFSDOWNSH
      rc2=$?
      echo $rc2
   fi

   sleep 10
   rm -f ${DATA}/*

done

#---------------------------------------------------
# Extract select records from GFS sfluxgrb files and
# convert to grib1 for archive and verfication use
if [ $CDUMP = "gfs" ]; then
    cd $COMOUT
    for fname in ${PREFIX}sfluxgrbf*grib2; do
       fhr3=$(echo $fname | cut -d. -f3 | cut -c 10-)
       fhr=$fhr3
       [ $fhr3 -lt 100 ] && fhr=$(echo $fhr3 | cut -c2-3)
       rm -f $DATA/outtmp
       $WGRIB2 $fname -match "(:PRATE:surface:)|(:TMP:2 m above ground:)" -grib $DATA/outtmp
       fileout=pgbq${fhr}.${CDUMP}.${CDATE}.grib1
       $CNVGRIB21_GFS -g21 $DATA/outtmp $DATA/$fileout
       $NCP $DATA/$fileout $COMOUT/$fileout
    done
fi

#----------------

[[ ${KEEPDATA:-NO} != YES ]] && rm -rf $DATA
err=$rc2
exit $err
