locals {

  
  cluster_files = fileset("regions", "*/location-*.yaml")
  directory = [for d in local.cluster_files : dirname("regions/${d}")]
  profile_files = fileset("regions", "*/profiles.yaml")

  clusters = try(yamldecode(join("\n", [for i in local.cluster_files : file("regions/${i}")])), [])
  profiles = { for f in local.profile_files :
    f => yamldecode(file("regions/${f}"))
  }
  edge = {
    for e in local.clusters :
    e.name => e
  }

  coordinates = {
    for cluster_name, location in data.http.location :
    cluster_name => {
      latitude  = jsondecode(location.body)[0].lat
      longitude  = jsondecode(location.body)[0].lon
    }
  }

}

resource "null_resource" "python_dependencies" {
  triggers = {
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "pip install -r modules/edge/requirements.txt"
  }
}

data "http" "location" {
  for_each = local.edge

  url = "https://nominatim.openstreetmap.org/search?q=${replace(each.value.city_and_state, " ", "+")}&format=json"
}

module "edge" {
  depends_on = [null_resource.python_dependencies]

  source                   = "./modules/edge"
  for_each                 = local.edge
  name                     = each.value.name
  skip_wait_for_completion = false
  cluster_tags             = each.value.cluster_tags
  cluster_vip              = each.value.cluster_vip
  ntp_servers              = each.value.ntp_servers
  node_pools               = each.value.node_pools
  cluster_profiles         = each.value.profiles
  latitude                 = local.coordinates[each.key].latitude
  longitude                = local.coordinates[each.key].longitude
  rbac_bindings            = each.value.rbac_bindings
  vault_role_names         = each.value.vault_role_names
  jwt_path = "jwt/${each.value.name}"
}

