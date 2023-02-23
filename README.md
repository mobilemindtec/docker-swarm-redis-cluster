# docker-swarm-redis-cluster
Docker swarm redis cluster


### Test

* Build images

`$ ./docker build`

* Start Swarm

`$ ./docker start`

* Log node manager
	
`$ ./docker logs`

* Open test app

`http://localhost:3000`


Funcionalidades
_______________

- O gerenciador aguarda todas os serviços subirem
- Descobre os IPs dos serviços
- Inicia o cluster com a lista de IPs descobertos
- Busca os IDs dos nós para cada serviço, baseado no IP
- Monitora quando um serviço muda de IP, no caso de reinicialização, realocação, etc..
- Quando um IP muda 
	* Tenta remover o nó do cluster
	* Adiciona o novo IP no cluster
	* Atualiza o IP e a lista de IDs


TODO
____

- Ver o que acontece quando a maquina gerenciadora reinicia, isso ainda não foi tratado nem testado	
	 