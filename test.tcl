#!/bin/tclsh

set result {
Could not connect to Redis at 10.0.1.80:6379: No route to host
Could not connect to Redis at 10.0.1.82:6379: No route to host
127.0.0.1:6379 (44074caa...) -> 0 keys | 5461 slots | 1 slaves.
10.0.1.75:6379 (5fb384d0...) -> 0 keys | 5462 slots | 1 slaves.
10.0.1.76:6379 (585ed894...) -> 0 keys | 5461 slots | 1 slaves.
10.0.1.83:6379 (51e25e6e...) -> 0 keys | 0 slots | 0 slaves.
[OK] 0 keys in 4 masters.
0.00 keys per slot on average.                                                                                                                 
>>> Performing Cluster Check (using node 127.0.0.1:6379)
M: 44074caac836c9796dfd1b374e95ad241abe9be9 127.0.0.1:6379
   slots:[0-5460] (5461 slots) master
   1 additional replica(s)
S: 5807e47c17cd37550dc34a7738d7edf15f75cf6d 10.0.1.77:6379
   slots: (0 slots) slave
   replicates 585ed894765aa796825ebcee1543e792d2e830d8
M: 5fb384d0ca1cf4c6eb5e6d5f32d5e977fba3fc7b 10.0.1.75:6379
   slots:[5461-10922] (5462 slots) master
   1 additional replica(s)
S: 63f30abf05af22669fe3ee7c2d2512e8ac23fabf 10.0.1.78:6379
   slots: (0 slots) slave
   replicates 44074caac836c9796dfd1b374e95ad241abe9be9
M: 585ed894765aa796825ebcee1543e792d2e830d8 10.0.1.76:6379
   slots:[10923-16383] (5461 slots) master
   1 additional replica(s)
M: 51e25e6eb970c7798e86d4d96ef281e2febe26c1 10.0.1.83:6379
   slots: (0 slots) master
S: 74afba277ee94bbac89e29f158836f1387b7c845 10.0.1.79:6379
   slots: (0 slots) slave
   replicates 5fb384d0ca1cf4c6eb5e6d5f32d5e977fba3fc7b
[OK] All nodes agree about slots configuration.
>>> Check for open slots...                                                                                                                    
>>> Check slots coverage...
[OK] All 16384 slots covered.  
}




proc get_nodes_id { data } {

  set lines [split $data \n]
  set nodes []

  foreach line $lines {

    #puts "line = $line"
    if {[string match "*M:*" $line] || [string match "*S:*" $line]} {
      lassign $line {} id ip
      puts "found = $id, $id"
      lappend nodes [dict create id $id ip [lindex [split $ip :] 0]]
    }

  }

  return $nodes

}


puts [get_nodes_id $result]