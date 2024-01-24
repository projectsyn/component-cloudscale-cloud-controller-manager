local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.cloudscale_cloud_controller_manager;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('cloudscale-cloud-controller-manager', params.namespace);

{
  'cloudscale-cloud-controller-manager': app,
}
