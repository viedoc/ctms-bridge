Write-Host "Build"

az bicep build --file "azuredeploy.bicep" --outfile "azuredeploy.json"

Write-Host "Push"

git add .
git commit -m "bicep -> arm build"
git push

Write-Host "Done"