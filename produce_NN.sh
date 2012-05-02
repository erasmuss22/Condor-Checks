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

calculateWait(){
	while read line
do
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
done <<< "`condor_q -run | grep $1`"
}

calculateStatistics(){
	echo $1
	prio=`echo "$1 + 0" | bc -l`
	echo $prio
	totalWait=0
for (( i=0;i<arrayPos-1;i++))
do
	let totalWait+=${waits[$i]}
done
if [ $arrayPos -gt 0 ]; then
	avgWait=`expr $totalWait / $arrayPos`		# As stated earlier arrayPos is array length at end
	bubblesort
	let MODULUS=$arrayPos%2
	if [ $MODULUS -eq 0 ]; then			# if number of jobs is even, take the average of 2 middle
		let half=$arrayPos/2			# values to get the median
		highMid=${waits[$half]}
		lowMid=${waits[$half-1]}
		median=`echo "($highMid+$lowMid)/2" | bc -l`
	else
		let half=$arrayPos/2			# if number of jobs is odd, median is middle value
		median=${waits[$half]}
	fi

	variance=0

	if [ $arrayPos -gt 4 ]; then
		lowerQuartilePos=`expr $arrayPos / 4`
		let upperQuartilePos=$lowerQuartilePos*3
		IQRlow=${waits[$lowerQuartilePos]}
		IQRhigh=${waits[$upperQuartilePos]}
		IQR=`expr $IQRhigh - $IQRlow`
		total=0
		for (( count=lowerQuartilePos;count<upperQuartilePos;count++))
		do
			let total+=${waits[count]}	
		done
		amount=`expr $upperQuartilePos - $lowerQuartilePos`
		avgWait=`expr $total / $amount`
		for (( count=lowerQuartilePos;count<upperQuartilePos;count++))
                do
                        temp=`expr ${waits[count]} - $avgWait`
			let variance+=$temp*$temp      
                done
		if [ $amount -gt 1 ]; then
			variance=`echo "($variance)/($amount-1)" | bc -l`
		else
			variance=`echo "($variance)/(1)" | bc -l`
		fi
		stdDev=`echo "sqrt($variance)" | bc -l`
		temp=`echo "($stdDev+0.5)/1" | bc`
		if [ $temp -gt 0 ]; then
			skew=`echo "($avgWait-$median)/$stdDev" | bc -l`
		else
			skew=0
		fi
	else
		for i in ${waits[@]}
		do
			temp=`expr $i - $avgWait`
			let variance+=$temp*$temp
		done
		variance=`echo "($variance)/$arrayPos" | bc -l`
		stdDev=`echo "sqrt($variance)" | bc -l`
		skew=`echo "($avgWait-$median)/$stdDev" | bc -l`
	fi
	echo $prio
	echo "Variance: $variance"
	echo "Standard Deviation: $stdDev"
	echo "Pearson's Skew: $skew"
	echo "$prio $avgWait $stdDev $median $skew $TOTAL $RUNNING $IDLE $HELD" >> /home/erasmussen/CondorScript/NN.txt
else
	exit 0
fi
}


OUTPUT=`condor_q | tail -1`
TOTAL=`echo $OUTPUT | cut -d ' ' -f1`
RUNNING=`echo $OUTPUT | cut -d ',' -f2 | cut -d ' ' -f2`
IDLE=`echo $OUTPUT | cut -d ';' -f2 | cut -d ' ' -f2`
HELD=`echo $OUTPUT | cut -d ';' -f2 | cut -d ',' -f3 | cut -d 'h' -f1`
echo $TOTAL
echo $IDLE
echo $RUNNING
echo $HELD

commands=false
if [ $# -eq 1 ]; then
	set `condor_userprio -allusers | grep $1`
	cmdLinePrio=$2
	cmdLinePrio=`echo "($cmdLinePrio+0.5)/1" | bc`
	echo "User Prio: $cmdLinePrio"
	commands=true
fi
userPos=0
priorityPos=0
resourcesPos=0
while read line
do
	if [[ "$line" == *"@"* ]]; then
		count=0
		for i in $line
		do
			if [ $count -eq 0 ]; then
				user[$userPos]=$i
				let userPos+=1
			elif [ $count -eq 1 ]; then
				priority[$priorityPos]=$i
				let priorityPos+=1
			elif [ $count -eq 4 ]; then
				resources[$resourcesPos]=$i
				let resourcesPos+=1
			fi
			let count+=1	
		done
	fi
done <<< "`condor_userprio -all`"
if [ $commands == 'true' ]; then
	count=0
	runningUsersPos=0
	runningPrioPos=0
	userLowPos=0
	userHighPos=0
	totalJobs=0
	for i in ${priority[@]}
	do
		i=`echo "($i+0.5)/1" | bc`
		echo $i
		if [ $i -le $cmdLinePrio ]; then
			if [ ${resources[$count]} -gt 0 ]; then
				echo $i
				runningUsers[$runningUsersPos]=`echo ${user[$count]} | cut -d '@' -f1`
				runningPrio[$runningPrioPos]=$i
				userLow[$userLowPos]=`expr $totalJobs + 1`
				let totalJobs+=${resources[$count]}
				userHigh[$userHighPos]=$totalJobs
				let runningUsersPos+=1
				let runningPrioPos+=1
				let userLowPos+=1
				let userHighPos+=1
			fi
			let count+=1
		fi
	done
	usersRunning=${#runningUsers[@]}
	echo $usersRunning
	if [ $usersRunning -eq 0 ]; then
		count=0
	        runningUsersPos=0
        	runningPrioPos=0
	        userLowPos=0
	        userHighPos=0
	        totalJobs=0
		for i in ${resources[@]}
        	do
	                if [ $i -gt 0 ]; then
	                        runningUsers[$runningUsersPos]=`echo ${user[$count]} | cut -d '@' -f1`
	                        runningPrio[$runningPrioPos]=${priority[$count]}
	                        userLow[$userLowPos]=`expr $totalJobs + 1`
	                        let totalJobs+=$i
	                        userHigh[$userHighPos]=$totalJobs
	                        let runningUsersPos+=1
	                        let runningPrioPos+=1
	                        let userLowPos+=1
	                        let userHighPos+=1
        	        fi
	                let count+=1
        	done
		COUNT=0
		arrayPos=0
		currentTime=`date +%s`
		echo ""
		ech $runningUsers[@]
		echo ${runningUsers[0]}
		calculateWait ${runningUsers[0]}
		calculateStatistics ${runningPrio[0]} 0
	else
		position=0
		lastUser=${#runningPrio[@]}
	        lastUser=`expr $lastUser - 1`
		for j in ${runningPrio[@]}
		do		
			COUNT=0
	                arrayPos=0
	                currentTime=`date +%s`
	                echo ""
			echo $j
	                echo ${runningUsers[$position]}
	                calculateWait ${runningUsers[$position]}
			if [ $position -eq 0 ]; then
        	        	calculateStatistics $j 0
			elif [ $position -eq $lastUser ]; then
				calculateStatistics $j 1
			else	
				calculateStatistics $j ${runningPrio[$position]}
			fi
			let position+=1
		done
	fi
else
	# filter out users who are running jobs
	count=0
	runningUsersPos=0
	runningPrioPos=0
	userLowPos=0
	userHighPos=0
	totalJobs=0
	for i in ${resources[@]}
	do
		if [ $i -gt 0 ]; then
			runningUsers[$runningUsersPos]=`echo ${user[$count]} | cut -d '@' -f1`
			runningPrio[$runningPrioPos]=${priority[$count]} 
			echo ${runningPrio[$runningPrioPos]}
			userLow[$userLowPos]=`expr $totalJobs + 1`
			let totalJobs+=$i
			userHigh[$userHighPos]=$totalJobs
			let runningUsersPos+=1
			let runningPrioPos+=1
			let userLowPos+=1
			let userHighPos+=1
		fi
		let count+=1
	done
	place=0
	currentTime=`date +%s`
	echo ${#runningUsers[@]}
	for k in ${runningPrio[@]}
	do
		echo ${runningPrio[$place]}
		echo "$k ${runningUsers[$place]} ${userLow[$place]} ${userHigh[$place]}"
		COUNT=0
	        arrayPos=0
	        calculateWait ${runningUsers[$place]}
	        calculateStatistics $k 0
		let place+=1
	done
fi
