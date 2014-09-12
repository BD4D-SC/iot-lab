#! /bin/bash -e

exp_id=$1
if [ ! "$exp_id" ]
then
    echo "Usage: $0 <experiment_id> [file listing no-ssh-access nodes] [log file]"
    echo "
       Flashes a8-m3 nodes and spawns a8-gw serial flooder
       on nodes that a.) deployed ok and b.) have ssh access
       for nodes belonging to specified experiment.
       Returns error status text if an error occured.
       Requires working ssh access to a8 nodes.
    "
    exit 1
fi

cd "$(dirname "$0")"
NODES_LIST=$(experiment-cli get -i $exp_id -p | ./parse_json.py "
	' '.join([str('node-'+node)
	for node in x['deploymentresults']['0']])")

# wait_for_ssh_access.sh, which should be called prior to this script,
# may fail on some nodes; failed nodes are passed as a file. Filter 'em out.

no_ssh=$(cat ${2:-/dev/null})
if [ "$no_ssh" ]; then
	NODES_LIST=$(echo "$NODES_LIST" | tr ' ' '\n' | grep -v "$no_ssh")
fi

NODES_ARRAY=($NODES_LIST)
printf "+ %-70s\r" "copying firmware to ${NODES_ARRAY[0]}"
scp ./firmware/serial_flood.a8.elf ${NODES_ARRAY[0]}: &> /dev/null
for node in $NODES_LIST
do 
    printf "+ %-70s\r" "running setup on $node"
    ssh $node 2>/dev/null '
	source /etc/profile
	ftdi-devices-list -t 2232 | grep -q Description \
		|| echo FTDI: No Open Node
	flash_a8.sh /home/root/serial_flood.a8.elf > /dev/null \
		|| echo Flash Firmware failed on m3
	serial_flooder() {
		while true; do cat /dev/mtd2 > /dev/null ; sleep 5; done
	}
	serial_flooder </dev/null &>/dev/null &
    ' > /tmp/$$.$node &
    [ $[ i = (i+1) % 10 ] = 0 ] && sleep 1
done
printf "+ %-70s\r" "waiting for setup to finish"
wait

logfile=${3:-/dev/stderr}
for node in $NODES_LIST
do
	out=$(cat /tmp/$$.$node | tr '\n' ' ')
	[ "$out" ] && echo "$node: $out" >> $logfile
	\rm /tmp/$$.$node
done
