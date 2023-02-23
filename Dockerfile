FROM redis:latest

RUN apt update && apt install -y tcl tcllib vim net-tools iputils-ping dnsutils


COPY conf/redis.conf /usr/local/etc/redis/redis.conf
#COPY monitor/main.tcl /entrypoint.tcl

COPY src/entrypoint.tcl /main/entrypoint.tcl
RUN chmod 755 /main/entrypoint.tcl

ENTRYPOINT ["/main/entrypoint.tcl"]

