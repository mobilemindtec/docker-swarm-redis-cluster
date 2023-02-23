FROM	debian:buster
RUN 	apt-get update && apt-get install -y curl && apt-get clean && rm -rf /var/lib/apt/lists
RUN		curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN		apt-get update && apt-get install -y nodejs 

RUN npm i nodemon -g

ADD	src /app
#RUN		cd /app; npm i --production 

WORKDIR /app

RUN npm i

EXPOSE  3000
CMD ["npm", "run", "dev"]
#CMD		[ "bash", "-c", "npm i && nodemon server.js"]