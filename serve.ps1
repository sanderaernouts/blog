New-Item -Type Directory -Path vendor/bundle -ErrorAction SilentlyContinue | Out-Null
docker run --rm --volume="$($PWD.Path):/srv/jekyll" --volume="$($PWD.Path)/vendor/bundle:/usr/local/bundle" -it jekyll/jekyll jekyll build
docker run --rm -p 4000:4000 -p 35729:35729 --volume="$($PWD.Path):/srv/jekyll" --volume="$($PWD.Path)/vendor/bundle:/usr/local/bundle" -it jekyll/jekyll jekyll serve --incremental --livereload