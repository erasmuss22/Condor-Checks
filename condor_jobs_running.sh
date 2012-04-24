#!/bin/bash
flip(){
	temp=${waits[$1]}
	waits[$1]=${waits[$2]}
	waits[$2]=$temp
}

bubblesort(){
	for (( last=arrayPos-1;last>0;last--))
	do
		for((i=0;i<last;i++))
		do
			j=$((i+1))
			if [ ${waits[i]} -gt ${waits[j]} ]
			 then
				flip $i $j
			fi
		done
	done
}

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
		if [[ "$line" == *"slot"* ]]; then 
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
					waits[$arrayPos]=$waitTime
					let arrayPos+=1				# final value of arrayPos is array length
				fi
				let INNER+=1
        	        done
		fi
		else
			let COUNT+=1
		fi
done <<< "`condor_q -run`"
#done <<< "`condor_q -constraint "JobStatus == 2"`"

totalWait=0
for i in ${waits[@]}
do
	let totalWait+=$i
done
if [ $arrayPos -gt 0 ]; then
	avgWait=`expr $totalWait / $arrayPos`		# As stated earlier arrayPos is array length at end
	echo $avgWait
	bubblesort
	let MODULUS=$arrayPos%2
	if [ $MODULUS -eq 0 ]; then			# if number of jobs is even, take the average of 2 middle
		let half=$arrayPos/2			# values to get the median
		highMid=${waits[$half]}
		lowMid=${waits[$half-1]}
		median=`echo "($highMid+$lowMid)/2" | bc -l`
		echo $highMid
		echo $lowMid
		echo $median
	else
		let half=$arrayPos/2			# if number of jobs is odd, median is middle value
		median=${waits[$half]}
		echo $median
	fi
	count=0
	variance=0
	for i in ${waits[@]}
	do
		waits[$count]=`expr $i - $avgWait`
		let variance+=${waits[$count]}*${waits[$count]}
		let count+=1
	done
	variance=`echo "($variance)/$arrayPos" | bc -l`
	stdDev=`echo "sqrt($variance)" | bc -l`
	skew=`echo "($avgWait-$median)/$stdDev" | bc -l`
	echo $variance
	echo $stdDev
	echo $skew
else
	exit 0
fi
#for i in ${waits[@]}
#do
#        echo $i
#done
