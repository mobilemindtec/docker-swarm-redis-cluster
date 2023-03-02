# docker-swarm-redis-cluster
Docker swarm redis cluster


### Test

* Build images

		`$ ./docker build`

* Start Swarm

		`$ ./docker deploy`

* Stop Swarm

		`$ ./docker stop`

* Logs node manager
	
		`$ ./docker logs`

* Logs app
		
		`$ ./docker logs-app`

* Logs nodes
		
		`$ ./docker logs-node1` # node1, node2, node3, ...

* Open test app

		`http://localhost:3000`


Funcionalidades
_______________

- Ao inciar o ADM, ele verifica se o cluster está on-line, solicitando o status dos nós baseado na ENV CLUSTER_NODES.

	- Se estiver on-line, adiciona a sí mesmo no clster 
	- Se não, inicia o cluster assim que 6 nós ingressarem no cluster

- Ao iniciar um NÓ, ele envia uma mensagem ao ADM solicitando ingresso no cluster

- Quando o cluster é criado, o ADM envia mensagem para todos os nós indicando que estão on-line
- Quando um novo nó é adicionado, o ADM envia uma mensagem ao nó informando que ele está on-line

- Assim que recebe o mansagem de que está on-line, o nó envia constantemente uma mensagem para o ADM informando estar on-line

	 