FROM ghcr.io/outsourc-e/hermes-workspace:latest

# // CREATE AN env file with values 
RUN echo "NODE_ENV=${NODE_ENV:-production}" >> /home/workspace/.hermes/.env
RUN echo "COOKIE_SECURE=${COOKIE_SECURE:-1}" >> /home/workspace/.hermes/.env