#!/bin/bash
GMETRIC="/usr/bin/gmetric"
OUTPUT=`condor_q | tail -1`
RUNNING=`echo $OUTPUT | cut -d ',' -f2 | cut -d ' ' -f2`
IDLE=`echo $OUTPUT | cut -d ';' -f2 | cut -d ' ' -f2`
$GMETRIC -n Condor_Jobs_Running -v $RUNNING -t uint16 -u 'Jobs'
$GMETRIC -n Condor_Queue_Length -v $IDLE -t uint16 -u 'Jobs'
COUNT=0
arrayPos=0
currentTime=`date +%s`
while read line
do
	if [ $COUNT -gt 3 ]; then
		INNER=0
		for i in $line
                do
			if [ $INNER -eq 2 ]; then
				MONTH=`echo $i | cut -d '/' -f1`
				DAY=`echo $i | cut -d '/' -f2`
				YEAR=`date +%Y`
				currentMonth=`date +%m`
				if [[ $MONTH -gt $currentMonth ]]; then
					let YEAR=$YEAR-1
				fi
				case $MONTH in
				1)
					MONTH="Jan"
				;;
				2)
					MONTH="Feb"
				;;
				3)	
					MONTH="Mar"
				;;
				4)
					MONTH="Apr"
				;;
				5)
					MONTH="May"
				;;
				6)
					MONTH="Jun"
				;;
				7)
					MONTH="Jul"
				;;
				8)
					MONTH="Aug"
				;;
				9)
					MONTH="Sep"
				;;
				10)
					MONTH="Oct"
				;;
				11)
					MONTH="Nov"
				;;
				12)
					MONTH="Dec"
				;;
				esac
				DATE="$MONTH $DAY, $YEAR"
			elif [ $INNER -eq 3 ]; then
				TIME=$i
				DATE=$DATE" $TIME"
				submitTime=`date \+\%s -d "$DATE"`
			elif [ $INNER -eq 4 ]; then
				DAYS=`echo $i | cut -d '+' -f1`
				DAYS=`expr $DAYS + 0`			# expr $VAR + 0 removes leading zeroes
				TEMP=`echo $i | cut -d '+' -f2`
				HOURS=`echo $TEMP | cut -d ':' -f1`
				HOURS=`expr $HOURS + 0`
				MINUTES=`echo $TEMP | cut -d ':' -f2`
				MINUTES=`expr $MINUTES + 0`
				SEC=`echo $TEMP | cut -d ':' -f3`
				SEC=`expr $SEC + 0`
				let DAYS=$DAYS*86400			# 86400 seconds in a day
				let HOURS=$HOURS*3600			# 3600 seconds in an hour
				let MINUTES=$MINUTES*60			# 60 seconds in a minute
				let sinceStart=$DAYS+$HOURS+$MINUTES+$SEC
				startTime=`expr $currentTime - $sinceStart`
				waitTime=`expr $startTime - $submitTime`
				echo $waitTime
				waits[$arrayPos]=$waitTime
				let arrayPos+=1				# final value of arrayPos is array length
			fi
			let INNER+=1
                done
	else
		let COUNT+=1
	fi

done <<< "`condor_q -constraint "JobStatus == 2"`"

totalWait=0
for i in ${waits[@]}
do
	let totalWait+=$totalWait+$i
	echo $totalWait
done
avgWait=`expr $totalWait / $arrayPos`		# As stated earlier arrayPos is array length at end
echo $avgWait
