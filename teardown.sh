
# set -x

rm -f ~/pan-plugin-user.json
rm -rf ~/bin

cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/cnseries"
kubectl delete -f ./sample-app/guestbook.yml

cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/cnseries/cn-series"
/bin/bash ./remove-cn.sh

cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/cnseries"
terraform destroy -auto-approve

cd "${HOME}/lab-aws-cn-series-zero-trust"
git reset --hard