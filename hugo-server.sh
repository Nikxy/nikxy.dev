docker run --rm -it \
  -v $(pwd):/src \
  -p 1313:1313 \
  --user 1000:1000 \
  klakegg/hugo \
  server