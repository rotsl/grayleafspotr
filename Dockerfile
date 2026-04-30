FROM rocker/shiny:4.5.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    python3 \
    python3-venv \
    python3-pip \
    libgl1 \
    libglib2.0-0 \
    libjpeg-dev \
    libtiff-dev \
    libpng-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/grayleafspotr-python \
    && /opt/grayleafspotr-python/bin/pip install --upgrade pip setuptools wheel

COPY inst/python/requirements_arm.txt /tmp/requirements_arm.txt
RUN sed 's/^opencv-python==/opencv-python-headless==/' /tmp/requirements_arm.txt > /tmp/requirements_render.txt \
    && /opt/grayleafspotr-python/bin/pip install -r /tmp/requirements_render.txt

ENV GRAYLEAFSPOTR_PYTHON=/opt/grayleafspotr-python/bin/python
ARG GRAYLEAFSPOTR_MODEL_URL="https://huggingface.co/rotsl/grayleafspot-segmentation/resolve/main/best_area_w_0.7.pt"

RUN R -e "install.packages(c('shiny', 'bslib', 'bsicons', 'DT', 'ggplot2', 'dplyr', 'jsonlite', 'readr', 'tibble', 'png', 'jpeg', 'tiff'), repos = 'https://cloud.r-project.org')"

WORKDIR /tmp/grayleafspotr-src
COPY . /tmp/grayleafspotr-src
RUN R CMD INSTALL . \
    && pkgdir=$(Rscript -e 'cat(system.file(package = "grayleafspotr"))') \
    && mkdir -p "$pkgdir/models" \
    && if [ -f /tmp/grayleafspotr-src/models/best_area_w_0.7.pt ]; then \
         cp -R /tmp/grayleafspotr-src/models/. "$pkgdir/models/"; \
       elif [ -n "$GRAYLEAFSPOTR_MODEL_URL" ]; then \
         curl -fL "$GRAYLEAFSPOTR_MODEL_URL" -o "$pkgdir/models/best_area_w_0.7.pt"; \
       else \
         echo "Missing models/best_area_w_0.7.pt. Force-add it to git or set GRAYLEAFSPOTR_MODEL_URL on Render."; \
         exit 1; \
       fi

RUN rm -rf /srv/shiny-server/* \
    && cp -R /tmp/grayleafspotr-src/inst/shiny/. /srv/shiny-server/ \
    && chown -R shiny:shiny /srv/shiny-server

EXPOSE 3838

CMD ["/bin/sh", "-c", "printf 'run_as shiny;\\nserver {\\n  listen %s;\\n  location / {\\n    app_dir /srv/shiny-server;\\n    log_dir /var/log/shiny-server;\\n  }\\n}\\n' \"${PORT:-3838}\" > /etc/shiny-server/shiny-server.conf && exec /usr/bin/shiny-server"]
