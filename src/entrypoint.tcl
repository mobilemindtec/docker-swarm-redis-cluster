#!/usr/bin/tclsh

package require logger 0.3

set log [logger::init main]


proc uniqkey { } {
  set key   [ expr { pow(2,31) + [ clock clicks ] } ]
  set key   [ string range $key end-8 end-3 ]
  set key   [ clock seconds ]$key
  return $key
}

proc get_host_addr {} {
  set cmdAddr [list ip a | grep eth0 | grep inet]
  set myAddr [exec {*}$cmdAddr]
  lassign $myAddr {} addr
  return [lindex [split $addr /] 0]
}

proc sleep { ms } {
  set uniq [ uniqkey ]
  set ::__sleep__tmp__$uniq 0
  after $ms set ::__sleep__tmp__$uniq 1
  vwait ::__sleep__tmp__$uniq
  unset ::__sleep__tmp__$uniq
}

proc every {delay script} {
    $script
    after $delay [info level 0]
}

set PORT 6379
set nodes []
set initiator false
set checkNodeActiveTryCount 0
set runTask 0
set myAddr [get_host_addr]
set myHostname cluster_initiator

set nodeMgrAddr $myAddr:$::PORT
set activeNodes []

${log}::info "current host addr = $myAddr"

if {[info exists ::env(NODES)]} {
  foreach var [split $::env(NODES) ,] {
    if {[string trim $var] != ""} {
      lappend nodes [dict create hostname $var ip "" id ""]
    }
  }

  lappend nodes [dict create hostname $myHostname ip $myAddr id ""]
}

if {[info exists ::env(INITIATOR)] && $::env(INITIATOR) == yes } {
  set initiator yes
}

proc get_host_address {hostname} {
  variable log
  set ip ""

  if { [catch { 

    set output [exec nslookup $hostname] 
    set results [split $output "\n"]
    
    if {[llength $results] > 2} {
      set output [lindex $results 5]
      set ip [split $output " "]
      set ip [lindex $ip [llength $ip]-1]
    }
    
    ${log}::info "found IP $ip to host $hostname"  

    } error] } {
      #puts "get_host_address - error on get ip from hostname $hostname: $error"
  }

  return $ip
}

proc discovery_nodes {addr} {
  variable log
  
  ${log}::info "run discovery nodes"

  upvar 1 ::nodes ns

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
        lassign $ln {} id ip
        set ip [lindex [split $ip :] 0]
        ${log}::debug "found id $id from IP $ip"
        lappend discoverd [dict create $ip $id]
      } 
    }

    # atualiza o IDS dos nodes
    for {set i  0} {$i < [llength $ns]} {incr i} {
      set node [lindex $ns $i]
      set ip [dict get $node ip]
      set hostname [dict get $node hostname]
      set foundId ""

      foreach it $discoverd {
        if {[dict exists $it $ip]} {
          set foundId [dict get $it $ip]
          break
        }
      }

      if {$foundId!=""} {
        dict set node id $foundId
        lset ns $i $node
        ${log}::info ":: set id $foundId to node $hostname, IP $ip"
      }
    }

  } error ] } {
    ${log}::error ":: error discovery nodes: $error"
  }
}

# check nodes activity
proc check_nodes_activity {} {

  variable log
  upvar 1 ::nodeMgrAddr masterAddr
  upvar 1 ::nodes ns 

  set ::activeNodes []

  for {set i  0} {$i < [llength $ns]} {incr i} {
    
    set node [lindex $ns $i]
    set hostname [dict get $node hostname]
    set ip [get_host_address $hostname]

    if { $hostname == $::myHostname } {
      lappend ::activeNodes $ip:$::PORT
      continue
    }

    
    if {$ip != ""} {
      ${log}::info "address $ip to node $hostname"
      # adiciona o IP dentro do Node
      dict set node ip $ip
      # atualiza o node dentro da lista global
      lset ns $i $node      
      ${log}::info "node = $node"
      # adiciona o IP dentro da lista de nodes ativos
      lappend ::activeNodes $ip:$::PORT
    } else {
      
      return false
    }
  }    
  return true
}


proc task_check_nodes_activity {} {

  variable log

  if {$::runTask == 0} {
    ${log}::info "not run task"
    set ::runTask 1
    return
  }

  upvar 1 ::nodes ns 
  upvar 1 ::nodeMgrAddr masterAddr

  for {set i 0} {$i < [llength $ns]} {incr i} {

    set node [lindex $ns $i]

    ${log}::info ":: check node $node activity"

    set hostname [dict get $node hostname]
    set currip [dict get $node ip]
    set currid [dict get $node id]
    set ipaddr [get_host_address $hostname]    

    if {"$ipaddr" != ""} {

      if { "$currip" != "$ipaddr" } {

        ${log}::info ":: node $hostname changed IP from $currip to $ipaddr"
        
        set cmdDelNode [join [list redis-cli --cluster del-node $masterAddr $currid --cluster-yes >@stdout]]

        set cmdAddNode [join [list redis-cli --cluster add-node $ipaddr:$::PORT $masterAddr --cluster-yes >@stdout]]


        if { [catch { 
          ${log}::info ":: to remove invalid cluster node, executing: $cmdDelNode"
          exec {*}$cmdDelNode
        } err] } {
          ${log}::error ":: error on REMOVE cluster node: $err"
        } 

        if { [catch { 
          ${log}::error ":: to add new cluster node, executing: $cmdAddNode"
          exec {*}$cmdAddNode
          
          ${log}::info ":: new node updated: $node"
        } err] } {
          ${log}::error ":: error on ADD cluster node: $err"
        } 

        dict set node ip $ipaddr
        # atualiza o node dentro da lista global
        lset ns $i $node   


      } else {
        ${log}::info ":: node $hostname is normal state"
      }

    } else {
      ${log}::info ":: node $hostname is off-line?"
    }
  }
}



${log}::info "init node.."

exec redis-server "/usr/local/etc/redis/redis.conf" >@stdout &

if {$initiator} {

  sleep 2000

  ${log}::info "current node is initiator node"

  if {[llength $nodes] == 0} {
    ${log}::info "no nodes to set"
    return
  }

  ${log}::info "start cluster with [llength $nodes] nodes"

  while {![check_nodes_activity]} {
    
    ${log}::info "run check_nodes_activity"

    # se não encontra o IP, espera e reinicia o processo
    if {$checkNodeActiveTryCount < 10} {
      set checkNodeActiveTryCount [expr $checkNodeActiveTryCount + 1]
      sleep 5000
      ${log}::info "check node activity again... count $checkNodeActiveTryCount"
    }    
  }

  if {[llength $activeNodes] == 0} {
    ${log}::info "no active nodes found"
    return
  }

  ${log}::info "wait to start cluster..."
  sleep 2000

  foreach node $nodes {
    ${log}::info "node = $node"
  }

  ${log}::info "configure cluster with [llength $activeNodes] nodes, activeNodes = $activeNodes"

  set iplist [join  $activeNodes]
  set cmdClusterCreate [join [list echo "yes" | redis-cli --cluster create $iplist --cluster-replicas 1 --cluster-yes >@stdout]]
  set cmdClusterInfo [join [list redis-cli --cluster check $nodeMgrAddr >@stdout]]
  
  ${log}::info "execute $cmdClusterCreate"
  if { [catch { 
    exec {*}$cmdClusterCreate
  } error] } {
    ${log}::error "error on execute cluster create: $error"
  }
  
  ${log}::info "execute $cmdClusterInfo"
  if { [catch { 
    exec {*}$cmdClusterInfo
  } error] } {
    ${log}::error "error on execute cluster info: $error"
  }

  discovery_nodes $nodeMgrAddr

  every 10000 task_check_nodes_activity

} else {
  ${log}::info "this is NOT initiator node"
}

vwait forever
