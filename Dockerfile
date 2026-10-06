# Dev/build image for the docs site. git is needed for Starlight's
# "Last updated" dates, which are read from commit history.
FROM node:22-alpine
RUN apk add --no-cache git
