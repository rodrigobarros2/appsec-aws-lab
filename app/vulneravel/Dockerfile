# ⚠️ VULNERÁVEL DE PROPÓSITO: imagem antiga e sem fixar, roda como root,
# copia tudo (inclusive arquivos locais) e usa CMD em forma de shell.
FROM node:14
WORKDIR /app
ADD . /app
RUN npm install
EXPOSE 8080
CMD npm start
