package require logger 0.3

set log [logger::init redis]


proc redis_node_delete {clusterNodeAttr nodeId} {
  
  variable log
  set cmd [join [list redis-cli --cluster del-node $clusterNodeAttr $nodeId --cluster-yes >&@stdout]]

  if { [catch { 
    ${log}::info ":: to remove invalid cluster node, executing: $cmd"
    exec {*}$cmd
  } err] } {
    ${log}::error ":: error on REMOVE cluster node: $err"
  }   
}

proc redis_node_add {clusterNodeAttr nodeAttr} {

  variable log

  set cmd [join [list redis-cli --cluster add-node $nodeAttr $clusterNodeAttr --cluster-yes >&@stdout]]


  if { [catch { 
    ${log}::error "to add new cluster node: $cmd"
    exec {*}$cmd

    ${log}::info "node $nodeAttr was added with success!!"
    #if {[string match "*New node added correctly*" $result]} {
    #} else {
    #  ${log}::error "node $nodeAttr NOT was added"
    #}

  } err] } {
    ${log}::error ":: error on ADD cluster node: $err"
  }   
}

proc redis_cluster_create {nodeAttr} {
  variable log  
  set cmd [join [list echo "yes" | redis-cli --cluster create $nodeAttr --cluster-replicas 1 --cluster-yes >&@stdout]]
  
  ${log}::info "execute $cmd"
  if { [catch { 
    exec {*}$cmd

    ${log}::info "cluster was created with success!!"
    #if {[string match "*All * slots covered*" $result]} {
    #} else {
    #  ${log}::error "cluster NOT was created"
    #}

  } error] } {
    ${log}::error "error on execute cluster create: $error"
  }  
}

proc redis_cluster_check {clusterNodeAttr} {
  variable log
  set cmd [join [list redis-cli --cluster check $clusterNodeAttr >&@stdout]]
  ${log}::info "execute $cmd"
  if { [catch { 
    exec {*}$cmd
  } error] } {
    ${log}::error "error on execute cluster info: $error"
  }  
}

proc redis_start {port} {
  variable log
  ${log}::info "init redis.."
  exec redis-server "/usr/local/etc/redis/redis.conf" --port $port >&@stdout &  
}