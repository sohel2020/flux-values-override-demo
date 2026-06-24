{{/*
spire-mount sidecar-injector partial template (rendered into the Istio CR's
`sidecarInjectorWebhook.templates.spire-mount` when `.Values.spire.enabled`
is true). Istio applies it as a strategic-merge overlay on top of the
upstream `sidecar` template (and on top of `gateway` for opted-in gateway
pods via the annotation `inject.istio.io/templates: "gateway,spire-mount"`).

Volumes-only partial: the upstream `sidecar` and `gateway` templates already
declare a `workload-socket` volume (as `emptyDir: {}`) and mount it onto
istio-proxy at `/var/run/secrets/workload-spiffe-uds`. We only need to swap
the volume's source from `emptyDir` to the SPIFFE CSI driver — istio-proxy
then reads its SVID from the SPIRE Workload API socket instead of istiod
xDS.

Why `$retainKeys`: strategic merge by default UNIONS fields of a matched
volume entry, which would leave both `emptyDir: {}` and `csi: {...}` set
("may not specify more than 1 volume type"). `$patch: replace` inside a
list element is interpreted as "replace the entire parent list", which
deletes every other upstream volume. `$retainKeys` is the strategic-merge
directive that surgically limits the result of merging this list element
to just the listed fields, leaving the rest of the list untouched. Drops
`emptyDir`, keeps `name` + `csi`.

Why no container/initContainer overlay: native-sidecar mode (k8s >=1.29)
puts istio-proxy in `initContainers`; legacy mode puts it in `containers`.
A partial that patches `containers` creates a phantom imageless istio-proxy
container on native sidecar pods. Since the upstream template already
declares the volumeMount, we don't need to touch the container at all.
*/}}
{{- define "istio-control-plane.spireMountTemplate" -}}
spec:
  volumes:
  - name: workload-socket
    $retainKeys:
      - name
      - csi
    csi:
      driver: csi.spiffe.io
      readOnly: true
{{- end -}}
