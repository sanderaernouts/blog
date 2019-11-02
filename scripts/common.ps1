function Start-JekyllContainer ($command) {
    $expression = "docker run --rm -p 4000:4000 -p 35729:35729 --volume=`"$($PWD.Path):/srv/jekyll`" --volume=`"$($PWD.Path)/vendor/bundle:/usr/local/bundle`" -it jekyll/jekyll $command"
    Invoke-Expression $expression
}