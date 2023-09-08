locals {
  profiles_list = fileset("${path.module}/regions", "**/profiles.yaml")

  profiles = {
    for p in local.profiles_list :
    trimsuffix(p, "/profiles.yaml") => yamldecode(file("regions/${p}"))
  }

  locations_files = fileset("${path.module}/regions", "**/location-*.yaml")

  locations_list = flatten([for l in local.locations_files : [
    for e in try(yamldecode(file("regions/${l}")), []) :
    merge({ profiles : local.profiles[replace(l, "//.*/", "")] }, e)
  ]])

  locations = {
    for e in local.locations_list :
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
    command = try("pip install -r modules/edge/requirements.txt")
  }
}

data "http" "location" {
  for_each = local.locations

  url = "https://nominatim.openstreetmap.org/search?q=${replace(each.value.city_and_state, " ", "+")}&format=json"
}

module "edge" {
  depends_on = [null_resource.python_dependencies]

  source                   = "./modules/edge"
  for_each                 = local.locations
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