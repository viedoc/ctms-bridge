$outFile = "azuredeploy.json"
$main = "main.bicep"

Write-Host "Building main.bicep ..."

az bicep build --file $main --outfile $outFile

Write-Host "Push"

git add .
git commit -m "bicep -> arm build"
git push

Write-Host "Done"