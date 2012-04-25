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
	totalWait=0
for i in ${waits[@]}
do
	let totalWait+=$i
done
if [ $arrayPos -gt 0 ]; then
	avgWait=`expr $totalWait / $arrayPos`		# As stated earlier arrayPos is array length at end
	if [ $2 -eq 0 ]; then
		echo "If Effective Priority <= $1, the average wait is: $avgWait"
	else
		echo "If Effective Priority is > $2 and <= $1, the average wait is: $avgWait"
	fi
	bubblesort
	let MODULUS=$arrayPos%2
	if [ $MODULUS -eq 0 ]; then			# if number of jobs is even, take the average of 2 middle
		let half=$arrayPos/2			# values to get the median
		highMid=${waits[$half]}
		lowMid=${waits[$half-1]}
		median=`echo "($highMid+$lowMid)/2" | bc -l`
		echo "High Middle: $highMid"
		echo "Low Middle: $lowMid"
		echo "Median: $median"
	else
		let half=$arrayPos/2			# if number of jobs is odd, median is middle value
		median=${waits[$half]}
		echo "Median: $median"
	fi

	variance=0

	if [ $arrayPos -gt 4 ]; then
		lowerQuartilePos=`expr $arrayPos / 4`
		let upperQuartilePos=$lowerQuartilePos*3
		IQRlow=${waits[$lowerQuartilePos]}
		echo "IQRlow: $IQRlow"
		IQRhigh=${waits[$upperQuartilePos]}
		echo "IQRhigh: $IQRhigh"
		IQR=`expr $IQRhigh - $IQRlow`
		echo "IQR: $IQR"
		total=0
		for (( count=lowerQuartilePos;count<upperQuartilePos;count++))
		do
			let total+=${waits[count]}	
		done
		amount=`expr $upperQuartilePos - $lowerQuartilePos`
		avgWait=`expr $total / $amount`
		echo "IQR average wait: $avgWait"
		for (( count=lowerQuartilePos;count<upperQuartilePos;count++))
                do
                        temp=`expr ${waits[count]} - $avgWait`
			let variance+=$temp*$temp      
                done
		variance=`echo "($variance)/($amount-1)" | bc -l`
		stdDev=`echo "sqrt($variance)" | bc -l`
		skew=`echo "($avgWait-$median)/$stdDev" | bc -l`
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
	echo "Variance: $variance"
	echo "Standard Deviation: $stdDev"
	echo "Pearson's Skew: $skew"
else
	exit 0
fi
}

userPos=0
priorityPos=0
resourcesPos=0
while read line
do
	if [[ "$line" == *"@"* ]]; then
		echo $line
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

# filter out users who are running jobs
count=0
runningUsersPos=0
runningPrioPos=0
userLowPos=0
userHighPos=0
totalJobs=0
for i in ${resources[@]}
do
	echo $i
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
count=0
for i in ${runningUsers[@]}
do
	echo "$i ${runningPrio[$count]} ${userLow[$count]} ${userHigh[$count]}"
	let count+=1
done

let MODULUS=$totalJobs%2
if [ $MODULUS -eq 0 ]; then			# if number of jobs is even, take the average of 2 middle
	let median=$totalJobs/2			# values to get the median
	echo "Median Job Number: $median"
else
	let half=$totalJobs/2			# if number of jobs is odd, median is middle value
	median=$half
	echo "Median Job Number: $median"
fi

count=0
lowUserPos=0
lowQuart=`expr $median / 2`
for i in ${runningUsers[@]}
do
        if [ ${userLow[$count]} -le $lowQuart ] && [ ${userHigh[$count]} -ge $lowQuart ]; then
                lowUser=$i
                lowUserPos=$count
        fi
        let count+=1
done

count=0
userPos=0
for i in ${runningUsers[@]}
do
	if [ ${userLow[$count]} -le $median ] && [ ${userHigh[$count]} -ge $median ]; then
		middleUser=$i
		userPos=$count
	fi
	let count+=1 
done

COUNT=0
arrayPos=0
currentTime=`date +%s`
echo ${runningUsers[0]}
calculateWait ${runningUsers[0]}
calculateStatistics ${runningPrio[0]} 0

COUNT=0
arrayPos=0
currentTime=`date +%s`
echo $middleUser
calculateWait "$lowUser"
calculateStatistics ${runningPrio[$lowUserPos]} ${runningPrio[0]}

COUNT=0
arrayPos=0
currentTime=`date +%s`
echo $middleUser
calculateWait "$middleUser"
calculateStatistics ${runningPrio[$userPos]} ${runningPrio[$lowUserPos]}


