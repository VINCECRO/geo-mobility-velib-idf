FROM rocker/shiny:4.4.2

ENV TZ=Europe/Paris

RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    libpq-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libudunits2-dev \
    libabsl-dev \
    cmake \
    && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages('shiny',        repos='https://cloud.r-project.org')"
RUN R -e "install.packages('bslib',        repos='https://cloud.r-project.org')"
RUN R -e "install.packages('bsicons',      repos='https://cloud.r-project.org')"
RUN R -e "install.packages('shinyWidgets', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('DBI',          repos='https://cloud.r-project.org')"
RUN R -e "install.packages('RPostgres',    repos='https://cloud.r-project.org')"
RUN R -e "install.packages('dplyr',        repos='https://cloud.r-project.org')"
RUN R -e "install.packages('lubridate',    repos='https://cloud.r-project.org')"
RUN R -e "install.packages('plotly',       repos='https://cloud.r-project.org')"
RUN R -e "install.packages('DT',           repos='https://cloud.r-project.org')"
RUN R -e "install.packages('pool',         repos='https://cloud.r-project.org')"
RUN R -e "install.packages('glue',         repos='https://cloud.r-project.org')"
RUN R -e "install.packages('scales',       repos='https://cloud.r-project.org')"
# Couches problématiques — binaires Posit pour éviter la compilation
RUN R -e "install.packages(c('sf','leaflet'), repos='https://packagemanager.posit.co/cran/__linux__/noble/latest')"


COPY app/ /srv/shiny-server/app/
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

EXPOSE 3838