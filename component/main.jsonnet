local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.cloudscale_cloud_controller_manager;
local isOpenShift = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

local manifests = std.parseJson(
  kap.yaml_load_stream(
    '%s/manifests/%s/config.yml'
    % [ inv.parameters._base_directory, params.manifests_version ]
  )
);

local patchDaemonset(obj) =
  if obj.kind == 'DaemonSet' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              if c.name == 'cloudscale-cloud-controller-manager' then
                c {
                  command+: params.args,
                }
              else
                c
              for c in super.containers
            ],
            [if isOpenShift then 'nodeSelector']: {
              'node-role.kubernetes.io/master': '',
            },
            [if isOpenShift then 'tolerations']+: [
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

local objKey(prefix, obj) =
  local sanitize(str) =
    std.asciiLower(std.strReplace(std.strReplace(str, '-', '_'), ':', '_'));
  local nsname = if std.objectHas(obj.metadata, 'namespace') then
    '%s_%s' % [ sanitize(obj.metadata.namespace), sanitize(obj.metadata.name) ]
  else
    obj.metadata.name;
  '%s_%s_%s' % [ prefix, sanitize(obj.kind), nsname ];

// NOTE(sg): We generate individual files for each object here so that we
// don't need to further process the rendered manifests to feed them to the
// OpenShift install process which requires that additional manifests are
// stored in individual files.
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
} + {
  [objKey('10_ccm', object)]: patchDaemonset(object) {
    metadata+: {
      namespace: params.namespace,
    },
  }
  for object in manifests
  if std.setMember(object.kind, [ 'DaemonSet', 'ServiceAccount' ])
} + {
  [objKey('20_rbac', object)]:
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
} + {
  [objKey('30_custom_rbac', object)]: object
  for object in customRBAC
}
