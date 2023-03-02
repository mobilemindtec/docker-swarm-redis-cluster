package require logger 0.3

set log [logger::init util]

proc uniqkey { } {
  set key   [ expr { pow(2,31) + [ clock clicks ] } ]
  set key   [ string range $key end-8 end-3 ]
  set key   [ clock seconds ]$key
  return $key
}

proc get_host_addr {} {

  if {[info exists ::env(INET)]} {
    set iface $::env(INET)
  } else {
    set iface eth0
  }

  set cmdAddr [list ip a | grep $iface | grep inet]
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
    
    #${log}::info "found IP $ip to host $hostname"  

    } error] } {
      #puts "get_host_address - error on get ip from hostname $hostname: $error"
  }

  return $ip
}