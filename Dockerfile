FROM rocker/shiny:4.5.3

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=10000

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
    libuv1 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/grayleafspotr-python \
    && /opt/grayleafspotr-python/bin/pip install --upgrade pip setuptools wheel

COPY inst/python/requirements_arm.txt /tmp/requirements_arm.txt
RUN sed \
      -e 's/^opencv-python==/opencv-python-headless==/' \
      -e '/^torch==/d' \
      -e '/^torchvision==/d' \
      /tmp/requirements_arm.txt > /tmp/requirements_render.txt \
    && /opt/grayleafspotr-python/bin/pip install --retries 10 --timeout 120 -r /tmp/requirements_render.txt \
    && /opt/grayleafspotr-python/bin/pip install --retries 10 --timeout 120 \
      --extra-index-url https://download.pytorch.org/whl/cpu \
      torch==2.11.0+cpu

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

EXPOSE 10000

USER shiny

CMD ["Rscript", "-e", "port <- as.integer(Sys.getenv('PORT', '10000')); options(shiny.host = '0.0.0.0', shiny.port = port); shiny::runApp('/srv/shiny-server', launch.browser = FALSE)"]
