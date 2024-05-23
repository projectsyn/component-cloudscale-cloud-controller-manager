local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.cloudscale_cloud_controller_manager;
local isOpenShift = inv.parameters.facts.distribution == 'openshift4';

local manifests = std.parseJson(
  kap.yaml_load_stream(
    '%s/manifests/%s/config.yml'
    % [ inv.parameters._base_directory, params.manifests_version ]
  )
);

local patchDaemonset(obj) =
  if isOpenShift && obj.kind == 'DaemonSet' then
    obj {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: {
              'node-role.kubernetes.io/master': '',
            },
            tolerations+: [
              {
                key: 'node-role.kubernetes.io/master',
                effect: 'NoSchedule',
              },
            ],
          },
        },
      },
    }
  else
    obj;

local tokenSecret = kube.Secret('cloudscale') {
  metadata+: {
    namespace: params.namespace,
  },
  data:: {},
  stringData: {
    'access-token': params.api_token,
  },
};

local customRBAC = if isOpenShift then
  [
    kube.RoleBinding('ccm-hostnetwork') {
      metadata+: {
        // Required if we want to deploy this manifest during cluster
        // bootstrap.
        namespace: params.namespace,
      },
      roleRef_: kube.ClusterRole('system:openshift:scc:hostnetwork'),
      subjects: [
        {
          kind: 'ServiceAccount',
          name: std.filter(
            function(obj) obj.kind == 'DaemonSet', manifests
          )[0].spec.template.spec.serviceAccountName,
          namespace: params.namespace,
        },
      ],
    },
  ]
else
  [];

{
  [if params.namespace != 'kube-system' then '00_namespace']:
    kube.Namespace(params.namespace) {
      metadata+: {
        annotations+: {
          // NOTE(sg): we set this unconditionally since it doesn't matter on
          // non-OCP.
          'openshift.io/node-selector': '',
        },
      },
    },
  '01_secret': tokenSecret,
  '10_daemonset': [
    patchDaemonset(object) {
      metadata+: {
        namespace: params.namespace,
      },
    }
    for object in manifests
    if std.setMember(object.kind, [ 'DaemonSet', 'ServiceAccount' ])
  ],
  '20_rbac': [
    object + if std.objectHas(object, 'subjects') then
      {
        subjects: [
          sub {
            namespace: params.namespace,
          }
          for sub in super.subjects
        ],
      }
    else
      {}
    for object in manifests
    if std.setMember(object.kind, [ 'ClusterRole', 'ClusterRoleBinding' ])
  ],
  [if std.length(customRBAC) > 0 then '30_custom_rbac']: customRBAC,
}
