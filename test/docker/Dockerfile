ARG NODE_IMAGE
FROM node:${NODE_IMAGE}
WORKDIR /deps
COPY package.json .
RUN npm install --ignore-scripts
WORKDIR /deps/app
CMD ["/deps/node_modules/.bin/mocha"]
