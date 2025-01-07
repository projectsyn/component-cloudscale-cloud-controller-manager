local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.cloudscale_cloud_controller_manager;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('cloudscale-cloud-controller-manager', params.namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/cloudscale-cloud-controller-manager' % appPath]: app,
}
