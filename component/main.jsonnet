// main template for cloudscale-cloud-controller-manager
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.cloudscale_cloud_controller_manager;

// Define outputs below
{
}
