#!/usr/bin/tclsh

package require logger 0.3
package require json

set log [logger::init entrypoint]

source "/main/util.tcl"
source "/main/redis.tcl"


set REDIS_PORT $::env(REDIS_PORT)
set SERVER_ADM_PORT $::env(SERVER_ADM_PORT)
set NODE_ADM_PORT $::env(NODE_ADM_PORT)

${log}::debug "$REDIS_PORT = $REDIS_PORT, SERVER_ADM_PORT = $SERVER_ADM_PORT, NODE_ADM_PORT = $NODE_ADM_PORT"

set REDIS_PORT [expr $REDIS_PORT * 1]
set SERVER_ADM_PORT [expr $SERVER_ADM_PORT * 1]
set NODE_ADM_PORT [expr $NODE_ADM_PORT * 1]
set NODES []
set IS_CLUSTER_ADM false
set MAX_TRY_ACTIVITY_CHECK 0
set MY_ADDR [get_host_addr]
set MY_HOST_NAME [info hostname]

${log}::debug "$MY_ADDR = $MY_ADDR, MY_HOST_NAME = $MY_HOST_NAME"

set NODE_ADM_ADDR $MY_ADDR:$::REDIS_PORT
set ACTIVE_NODES []

set CURR_STATUS offline

if {[info exists ::env(CLUSTER_ADM)] && $::env(CLUSTER_ADM) == yes } {
  set IS_CLUSTER_ADM true
}

if {$IS_CLUSTER_ADM} {
  set SRV_PORT $SERVER_ADM_PORT 
} else {
  set SRV_PORT $NODE_ADM_PORT
}


${log}::debug "$SRV_PORT"


proc discovery_nodes_ids {addr} {
  variable log
  
  ${log}::debug "run discovery nodes ids"

  upvar 1 ::NODES nodes

  if { [ catch {
    set cmd [join [list redis-cli --cluster check $addr]]
    set result [exec {*}$cmd]
    set lines [split $result \n]
    set discoverd []

    #${log}::debug "ckeck result = $result"

    # busca os IDS dos nodes
    foreach line $lines {    
      set ln [string trim $line]
      
      if {[string match "*M:*" $ln] || [string match "*S:*" $ln]} {
        lassign $ln {} id addr
        set addr [lindex [split $addr :] 0]
        ${log}::debug "found id $id from IP $addr"
        lappend discoverd [dict create $addr $id]
      } 
    }

    # atualiza o IDS dos nodes
    for {set i  0} {$i < [llength $nodes]} {incr i} {
      set node [lindex $nodes $i]
      set addr [dict get $node addr]
      set hostname [dict get $node hostname]
      set foundId ""

      foreach it $discoverd {
        if {[dict exists $it $addr]} {
          set foundId [dict get $it $addr]
          break
        }
      }

      if {$foundId!=""} {
        dict set node id $foundId
        lset nodes $i $node
        ${log}::info "set id $foundId to node $hostname, IP $addr"
      }
    }

  } err ] } {
    ${log}::error "error discovery nodes: $err"
  }
}

proc task_check_nodes_activity {} {

  variable log

  upvar 1 ::NODES nodes 
  set needDiscovery false
  set offlineNodes []

  for {set i 0} {$i < [llength $nodes]} {incr i} {

    set node [lindex $nodes $i]
    set hostname [dict get $node hostname]
    set addr [dict get $node addr]
    set status [dict get $node status]
    set port [dict get $node port]
    set id [dict get $node id]

  
    ${log}::info "check node $hostname state: $status"

    set currAddr [get_host_address $hostname]

    if {$status == "offline"} {
      redis_node_add $::MY_ADDR:$::REDIS_PORT $addr:$port

      set needDiscovery true

      # atualiza o node dentro da lista global
      dict set node status online
      lset nodes $i $node   

      send_cluster_msg set_online $node 

    } else {      

      if { $currAddr != $addr } {
        ${log}::info "node $hostname ip changes from $addr to $currAddr, set node offline"     
        lappend offlineNodes $node
      }
    }
  } 

  set newNodes []

  foreach n $nodes {
    set remove false
    foreach r $offlineNodes {
      if {[dict get $n addr] == [dict get $r addr]} {
        set remove true
      }
    }
    if {!$remove} {
      lappend newNodes $n
    } else {
      redis_node_delete $::MY_ADDR:$::REDIS_PORT [dict get $n id]
    }
  }

  set ::NODES $newNodes

  if {$needDiscovery} {
    discovery_nodes_ids $::MY_ADDR:$::REDIS_PORT
  }
}

proc sender_handler_r {socket msg cb} {
  variable log

  ${log}::debug "receive new response from node: $msg"

  if {[catch {
    if {$cb!=""} {
      set response [gets $socket]
      ${log}::debug "sender response: $response"
      lappend cb [response2dict $response]
      {*}$cb    
    }
  } err ]} {
    ${log}::error "sender_handler error: $err"
  }
  close $socket
}

proc sender_handler_w {socket msg cb} {

  variable log

  ${log}::debug "send new message to node: $msg"

  if {[catch {
    puts $socket $msg
    flush $socket

    if {$cb==""} {
      close $socket
    }
  } err ]} {
    ${log}::error "sender_handler error: $err"
  }
}

# 
# msg_type ingresss, data = ""
# msg_type online, data = [dict create addr ""]
# msg_type status, data = [dict create addr "" cb ""]
#
proc send_cluster_msg {msgType {data {}}} {
  variable log
  

  set params []
  set server cluster_adm
  set cb ""

  switch $msgType {
    ingress {
      set msg msg_type=ingress&hostname=$::MY_HOST_NAME&addr=$::MY_ADDR&port=$::REDIS_PORT
      set params [list $msg ""]
    }
    set_online {
      set addr [dict get $data addr]
      set msg msg_type=set_online
      set params [list $msg ""]
      set server $addr
    }
    get_status {
      set addr [dict get $data addr]
      set cb [dict get $data cb]
      set msg msg_type=get_status
      set params [list $msg $cb]
      set server $addr
    }
    node_online {
      set msg msg_type=node_online&hostname=$::MY_HOST_NAME&addr=$::MY_ADDR&port=$::REDIS_PORT
      set params [list $msg ""]
    }
    default {
      ${log}::error "message type unknown: $msg_type"
    }
  }

  ${log}::debug "send cluster msg $msgType to $server"

  if {[llength $params] > 0} {

    if {[catch {

      #${log}::debug "send message type $msgType to $server"

      set socket [socket $server $::SERVER_ADM_PORT]
      fconfigure $socket -blocking 0
      #fileevent $socket writable [list sender_handler $socket {*}$params]
      #fileevent $socket readable [list sender_handler_r $socket {*}$params ]

      fileevent $socket writable {}

      puts $socket $msg
      flush $socket


      if {$cb!=""} {
        fileevent $socket readable {}
        sleep 2        
        set response [gets $socket]
        ${log}::debug "sender response: $response"
        lappend cb [response2dict $response]
        {*}$cb    
      }

      close $socket

      #sender_handler $socket {*}$params
      return true
    } stat]} {

      if {$stat == true} {
        return $stat
      }

      if {[dict exists $data cb]} {
        set cb [dict get $data cb]
        lappend cb [dict create status offline]
        {*}$cb
      }

      ${log}::error "error on connect $server, with msg type $msgType: $stat"
    }          
  }

  return false
}

proc response2dict {response} {
  set fields [split [lindex [split $response \n] 0] &]
  set data [dict create]
  foreach f $fields {
    set kv [split $f =]
    dict set data [lindex $kv 0] [lindex $kv 1]
  }  
  return $data
}

proc message_handler {socket addr port} {

  variable log

  fileevent $socket readable {}  
  fconfigure $socket -translation auto -buffersize 4096

  if { [eof $socket]} {
    ${log}::debug "channel closed"
    close $socket
    return
  }

  set content [gets $socket]
  set data [response2dict $content]


  if {![dict exists $data msg_type]} {
    ${log}::info "ignore empty message"
    close $socket
    return
  }
  
  set msgType [dict get $data msg_type]

  switch $msgType {
    ingress {
      set hostname [dict get $data hostname]
      set port [dict get $data port]
      set addr [dict get $data addr]
      lappend ::NODES [dict create hostname $hostname addr $addr id "" port $port status offline]            
      
      ${log}::debug "new message received: $msgType from $hostname"
      
      puts $socket status=complete
    }
    get_status {
      ${log}::debug "new message received: $msgType from cluster adm"
      puts $socket status=$::CURR_STATUS&addr=$::MY_ADDR&port=$::REDIS_PORT
    }
    set_online {
      ${log}::debug "new message received: $msgType from cluster adm"
      set ::CURR_STATUS online
      puts $socket status=complete
    }
    node_online {
      set hostname [dict get $data hostname]
      set port [dict get $data port]
      set addr [dict get $data addr]

      ${log}::debug "new message received: $msgType from $hostname"

      set found false

      foreach node $::NODES {
        if { "[dict get $node hostname]" == "$hostname" || "[dict get $node addr]" == "$addr" } {
          set found true
          break
        }
      }

      if {!$found} {
        lappend ::NODES [dict create hostname $hostname addr $addr id "" port $port status online]
      }

      puts $socket status=complete
    }
    default {
      set msg "message type not handled: $msgType"
      ${log}::info $msg
      puts $socket $msg
    }
  }

  close $socket
}

proc check_node_is_up_resp {nodes idx resp} {

  variable log
  set node [lindex $nodes $idx]
  set nextIdx [expr $idx + 1]

  ${log}::debug "check_node_is_up_resp resp = $resp, idx = $idx, next = $nextIdx"

  if {$resp==""} {
    set status offline
  } else {
    set status [dict get $resp status]
  }

  if {$status=="online"} {
    
    set addr [dict get $resp addr]
    set port [dict get $resp port]

    dict set node addr $addr
    dict set node port $port

    cluster_start [dict create status online addr $addr port $port]

  } else {
    check_node_is_up $nodes $nextIdx
  }
}

proc check_node_is_up {nodes idx} {
  
  variable log


  if {$idx >= [llength $nodes]} {
    cluster_start [dict create status offline]
  } else {
    set node [lindex $nodes $idx]
    set addr [dict get $node addr]
    
    ${log}::debug "check node $addr is up"

    send_cluster_msg get_status [dict create addr $addr cb [list check_node_is_up_resp $nodes $idx]]
  }
}

proc check_cluster_is_up {} {

  variable log

  ${log}::debug "check cluster is up"

  set envNodes $::env(CLUSTER_NODES)
  set nodes []

  foreach n [split $envNodes ,] {
    set kv [split $n :]
    lappend nodes [dict create addr [lindex $kv 0] port [lindex $kv 1]]
  }

  check_node_is_up $nodes 0
}

proc cluster_start {curr} {

  variable log
  set status "offline"

  if {[dict exists $curr status]} {
    set status [dict get $curr status]
  }  

  if {$status == "online"} {

    set addr [dict get $curr addr]
    set port [dict get $curr port]

    ${log}::info "cluster already on-line!, ingresse on cluster by $addr:$port"

    redis_node_add $addr:$port $::MY_ADDR:$::REDIS_PORT

  } else {    

    while {[llength $::NODES] < 6} {
      ${log}::info "waiting by 6 nodes ingress, currentily [llength $::NODES] nodes"
      sleep 5000
    }  

    ${log}::info "cluster init"

    set addrlist [list $::MY_ADDR:$::REDIS_PORT]

    for {set i  0} {$i < [llength $::NODES]} {incr i} {
      set node [lindex $::NODES $i]
      set addr "[dict get $node addr]:[dict get $node port]"
      dict set node status online
      lset ::NODES $i $node
      lappend addrlist $addr

    }

    # create cluster
    redis_cluster_create [join $addrlist]

    sleep 2000

    foreach node $::NODES {
      send_cluster_msg set_online $node
    }
  }
  
  # run cluster check to output 

  every 10000 task_check_nodes_activity


  discovery_nodes_ids $::MY_ADDR:$::REDIS_PORT
}

proc task_node_online {} {
  variable log
  if {$::CURR_STATUS == "online"} {
    send_cluster_msg node_online
  } else {
    ${log}::debug "node offline"
  }
}

proc node_start {} {
  redis_start $::REDIS_PORT
  
  set done false
  # try ingress node on cluster
  while {!$done} {
    set done [send_cluster_msg ingress]
    sleep 5000
  }
}


${log}::info "start service on port $SRV_PORT"
# init service socket to message receive
set socket [socket -server message_handler $SRV_PORT]

# wait by node ingress to init cluster
if {$IS_CLUSTER_ADM} {

  redis_start $REDIS_PORT

  sleep 2000

  check_cluster_is_up
    
} else {

  ${log}::info "this is NOT initiator node"

  node_start

  every 10000 task_node_online

}

${log}::info "NODE STARTED WITH ADM ${IS_CLUSTER_ADM}"

vwait forever