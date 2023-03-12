data "local_file" "pem_file" {
  depends_on = [null_resource.write_pem]
  filename = "${path.module}/pem_${local.cluster_id}.pub"
}

resource "local_file" "kubeconfig" {
  content  = spectrocloud_cluster_edge_native.this.kubeconfig
  filename = "kubeconfig_${local.cluster_id}"
}

# null provider reading a file
resource "null_resource" "write_pem" {
  depends_on = [local_file.kubeconfig]
  triggers = {
    # change this if a force re-run is needed
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "python3 ${path.module}/read_pem_from_oidc.py >> ${path.module}/pem_${local.cluster_id}.pub"
    environment = {
      KUBECONFIG = local_file.kubeconfig.filename
    }
  }
}


resource "vault_jwt_auth_backend" "this" {
  type = "jwt"
  jwt_validation_pubkeys = [data.local_file.pem_file.content]
  # path = "demo"
}

resource "vault_jwt_auth_backend_role" "this" {
  backend                          = vault_jwt_auth_backend.this.path
  role_name                        = "devweb-app"
  bound_audiences = ["https://kubernetes.default.svc.cluster.local"]
  bound_subject = "system:serviceaccount:default:default"
  token_policies = ["devwebapp"]
  user_claim = "sub"
  role_type       = "jwt"

}

