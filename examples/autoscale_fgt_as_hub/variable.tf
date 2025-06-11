# Project vars
variable "prefix" {
  type        = string
  description = "Prefix of all objects in this module. It should be unique to avoid name conflict between projects."
  validation {
    condition     = (can(regex("^[a-z][a-z0-9-]*$", var.prefix)) || var.prefix == "") && length(var.prefix) <= 15
    error_message = "The prefix must start with a letter, can only contain lowercase letters, numbers, and hyphens, and must not exceed 15 characters."
  }
}

variable "project" {
  type        = string
  description = "Your GCP project name."
}

variable "region" {
  type        = string
  description = "The region to deploy the project."
}

variable "zone" {
  type        = string
  description = <<-EOF
  Deploy the project to this single zone.
  Variable "zone" is mutually exclusive with variable "zones".
  If both zone and zones are specified, zones will be used.
  If both are unspecified, GCP will select 3 zones for you.
  EOF
  default     = ""
}

variable "zones" {
  type        = list(string)
  description = <<-EOF
  Deploy the project to multiple zones for higher availability.
  Variable "zones" is mutually exclusive with variable "zone".
  If both zone and zones are specified, zones will be used.
  If both are unspecified, GCP will select 3 zones for you.
  EOF
  default     = []
}

# IAM
variable "service_account_email" {
  type        = string
  default     = ""
  description = <<-EOF
  Example value: 1234567-compute@developer.gserviceaccount.com
  The e-mail address of the service account. This service account will control the cloud function created by this project.
  This service account should already have "roles/datastore.user" and "roles/compute.viewer".
  If this variable is not specified, the default Google Compute Engine service account is used.
  EOF 
}

# FGT vars
variable "fgt_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = <<-EOF
  Password for all FGTs (user name is admin). It must be at lease 8 characters long if specified.
  If no password is set, the module will randomly generate a 16-character password.
  After the deployment, if you change the "admin" user password elsewhere (e.g., through the GUI or CLI),
  please ensure you also update the password here to allow the Cloud Function to communicate with the FortiGates.
  EOF

  validation {
    condition = (
      var.fgt_password == "" || length(var.fgt_password) > 8
    )
    error_message = "The fgt_password must be at least 8 characters long if specified."
  }
}

variable "fgt_hostname" {
  type        = string
  default     = ""
  description = <<-EOF
  The hostname of all FGTs in the autoscale group. If not specified, the FGT's hostname will be its serial number.
  EOF
}

variable "machine_type" {
  type        = string
  description = <<-EOF
    The Virtual Machine type to deploy FGT. Example of predefined type: n1-standard-4, n2-standard-8, ...

    Custom machine types can be formatted as custom-NUMBER_OF_CPUS-AMOUNT_OF_MEMORY_MB,
    e.g. custom-6-20480 for 6 vCPU and 20GB of RAM.

    There is a limit of 6.5 GB per CPU unless you add extended memory. You must do this explicitly by adding the suffix -ext,
    e.g. custom-2-15360-ext for 2 vCPU and 15 GB of memory.
  EOF
}

variable "image_type" {
  type        = string
  default     = "fortigate-76-byol"
  description = <<-EOF
  The type of public FortiGate Image. Example: "fortigate-76-byol" or "fortigate-76-payg"
  One of the variables "image_type" and "image_source" must be provided, otherwise an error occurs. If both are provided, "image_source" will be used.
  Use the following command to check all FGT image type:
  `gcloud compute images list --project=fortigcp-project-001 --filter="family:fortigate*" --format="table[no-heading](family)" | sort | uniq`

  fortigate-76-byol : FortiGate 7.6, bring your own licenses.
  
  fortigate-76-payg : FortiGate 7.6, don't need to provide licenses, pay as you go.
  EOF
}

variable "image_source" {
  type        = string
  default     = ""
  description = <<-EOF
  The source of the custom image. Example: "projects/fortigcp-project-001/global/images/fortinet-fgt-760-20240726-001-w-license"
  One of the variables "image_type" and "image_source" must be provided, otherwise an error occurs. If both are provided, "image_source" will be used.
  EOF
}

variable "additional_disk" {
  type = object({
    size = optional(number, 0)
    type = optional(string, "pd-standard")
  })
  default = {
    size = 0
    type = "pd-standard"
  }
  description = <<-EOF
    Additional disk for logging.

    Options:

        - size : (Optional | number | default:0) Log disk size (GB) for each FGT. If set to 0, no additional log disk is created.
        - type : (Optional | string | default:"pd-standard") The Google Compute Engine disk type. Such as "pd-ssd", "local-ssd", "pd-balanced" or "pd-standard".

    Example:
    ```
    additional_disk = {
      size = 30
      type = "pd-standard"
    }
    ```
  EOF
}

# Network
variable "network_interfaces" {
  type = list(object({
    network_name  = string
    subnet_name   = string
    has_public_ip = optional(bool, false)
    internal_lb = optional(object({
      front_end_ip         = optional(string, "")
      frontend_protocol    = optional(string, "TCP")
      backend_protocol     = optional(string, "TCP")
      ip_range_route_to_lb = optional(string, "")
      })
    )
    additional_variables = optional(map(string), {})
  }))
  description = <<-EOF
    Network interfaces.

    Options:

        - network_name  : (Required | string) The name of your existing VPC.
        - subnet_name   : (Required | string) The name of your existing subnet under the "network_interfaces.network_name".
        - has_public_ip : (Optional | bool | default:false) Whether this port has a public IP. The default is False.
        - internal_lb   : (Optional | object) If "internal_lb" is specified, an internal load balancer will be created in the "subnet_name" subnet.
            - front_end_ip : (Optional | string | default:"") The IP of your internal load balancer. If not specified, GCP will select an IP for you.
            - frontend_protocol : (Optional | string | default:"TCP") Protocol of the front-end forwarding rule. Valid options are TCP, UDP, ESP, AH, SCTP, ICMP and L3_DEFAULT.
            - backend_protocol : (Optional | string | default:"TCP") The protocol the load balancer uses to communicate with the backend. Valid options are HTTP, HTTPS, HTTP2, SSL, TCP, UDP, GRPC, UNSPECIFIED.
            - ip_range_route_to_lb : (Optional | string | default:"") If "ip_range_route_to_lb" is specified, a route will be created in the "subnet_name" subnet.
                  All traffic to "ip_range_route_to_lb" will be routed to the internal load balancer (ilb) in this subnet.
        - additional_variables : (Optional | object) Additional variables.
            - ilb_ip : (Optional | string) The IP of your internal load balancer.
                  If you don't specify internal_lb and specify ilb_ip here instead, this Terraform project only tells the FGTs the IP of ILB, and doesn't create ILB in GCP.

    Example:
    ```
    network_interfaces = [                     # Network interface of your FortiGate
      # Port 1 of your FortiGate. For this interface, this prject creates an internal load balancer (ILB) and a route to the ILB.
      {
        network_name  = "user1-network"        # Name of your network.
        subnet_name   = "user1-subnet"         # Name of your subnet.
        has_public_ip = true                   # Whether FortiGates in this network have public IP. Default is false.
        internal_lb   = {                      # If "internal_lb" is specified, an internal load balancer will be created in the "subnet_name" subnet.
          ip_range_route_to_lb = "10.0.0.0/8"  # If "ip_range_route_to_lb" is specified, a route will be created in the "subnet_name" subnet.
                                               # And all traffic to "ip_range_route_to_lb" will be routed to the internal load balancer (ilb) in this subnet.
        }
      },
      # Port 2 of your FortiGate. For this interface, this prject creates an internal load balancer (ILB). (No route to the ILB).
      {
        network_name = "user2-network"
        subnet_name  = "user2-subnet"
        internal_lb  = {}
      },
      # Port 3 of your FortiGate. No ILB and route to ILB will be created. Using existing ILB instead.
      # You need to manually add the FGT instance group as the backend of the existing ILB in Google Cloud after the deployment of this example project.
      {
        network_name = "user3-network"
        subnet_name  = "user3-subnet"
        additional_variables = {
          ilb_ip = "10.2.0.100"
        }
      },
      # Port 4 of your FortiGate. This interface doesn't specify "internal_lb", so no ILB and route to ILB will be created.
      {
        network_name = "user4-network"
        subnet_name  = "user4-subnet"
      },
      # You can specify more ports here
      # ...
    ]
    ```
  EOF
}

variable "network_tags" {
  type        = list(string)
  default     = []
  description = <<-EOF
  The list of network tags attached to FortiGates.
  GCP firewall rules have "target tags", and these firewall rules only apply to instances with the same tag.
  You can specify the tags here.
  EOF
}

variable "ha_sync_interface" {
  type        = string
  description = <<-EOF
  The port used to sync data between FortiGates. Example values: "port1", "port2", "port3"... 
  If you specified 8 interfaces in "network_interfaces",
  then the first interface is "port1", the second one is "port2", the last one is "port8".
  
  Example:
    ```
    # Please make sure you at least have 4 interfaces specified in "network_interfaces" if you set it to "port4".
    ha_sync_interface = "port4"   
    ```
  EOF
  validation {
    condition     = can(regex("^port[1-8]$", var.ha_sync_interface))
    error_message = "The ha_sync_interface must be one of 'port1', 'port2', ..., 'port8'."
  }
}

# Cloud function
variable "cloud_function" {
  type = object({
    cloud_func_interface = optional(string, "port1")
    function_ip_range    = string
    license_source       = optional(string, "none")
    license_file_folder  = optional(string, "./licenses")
    autoscale_psksecret  = optional(string, "psksecret")
    logging_level        = optional(string, "NONE")
    fortiflex = optional(object({
      retrieve_mode = optional(string, "use_stopped")
      username      = optional(string, "")
      password      = optional(string, "")
      config        = optional(string, "")
    }), {})
    service_config = optional(object({
      max_instance_count               = optional(number, 1)
      max_instance_request_concurrency = optional(number, 10)
      available_cpu                    = optional(string, "1")
      available_memory                 = optional(string, "1G")
      timeout_seconds                  = optional(number, 240)
      ingress_settings                 = optional(string, "ALLOW_ALL")
      egress_settings                  = optional(string, "PRIVATE_RANGES_ONLY")
    }), {})
    build_service_account_email = optional(string, "")
    trigger_service_account_email = optional(string, "")
    additional_variables        = optional(map(string), {})
  })
  description = <<-EOF
    Parameters for Cloud Function. The Cloud Function is used to inject licenses to FGTs,
    upload user-specified configurations and manage the FGT autoscale group.

    Options:

        - cloud_func_interface : (Optional | string | default:"port1")
          To communicate with FGTs, the Cloud Function must be connected to the VPC where FGTs also exist.
          By default, this project assumes the Cloud Function connects to the first VPC you specified in "network_interfaces", and configure your FGTs through port1.
          You can also set it to "port2", "port3", ..., "port8" to force the Cloud Function to connect to other VPC and communicate with your FortiGates through that port,
          but you need to specify the corresponding route of FGTs in "config_script" or "config_file" so FGTs can reply to the Cloud Function requests from "cloud_function.function_ip_range".
        - function_ip_range : (Required | string) Cloud function needs to have its only CIDR ip range ending with "/28", which cannot be used by other resources. Example "10.1.0.0/28".
          This IP range subnet cannot be used by other resources, such as VMs, Private Service Connect, or load balancers.
          A static route will be created in the FGT that routes data destined for "cloud_function.function_ip_range" to port "cloud_function.cloud_func_interface".
        - license_source : (Optional | string | default:"none") The source of license if your image_type is "byol".
            "none" : Don't inject licenses to FGTs.
            "file" : Injecting licenses based on license files. All license files should be in license_file_folder.
            "fortiflex" : Injecting licenses based on FortiFlex. Need to specify the parameter fortiflex if license_source is "fortiflex".
            "file_fortiflex" : Injecting licenses based on license files first. If all license files are in use, try FortiFlex next.
        - license_file_folder : (Optional | string | default:"./licenses") The folder where all ".lic" license files are located. Default is "./licenses" folder.
        - autoscale_psksecret : (Optional | string | default:"psksecret") The secret key used to synchronize information between FortiGates. If not set, the module will randomly generate a 16-character secret key.
        - logging_level : (Optional | string | default:"INFO") Verbosity of logs. Possible values include "NONE", "ERROR", "WARN", "INFO", "DEBUG", and "TRACE". You can find logs in Google Cloud Logs Explorer.
        - fortiflex: (Optional | object) You need to specify this parameter if your license_source is "fortiflex" or "file_fortiflex".
            - retrieve_mode : (Optional | string | default:"use_stopped") How to retrieve an existing fortiflex license (entitlement):
                "use_stopped" Retrieves "STOPPED", "EXPIRED" or "PENDING" licenses, and changes them to "ACTIVE". If the license is released, change the license to "STOPPED".
                "use_active" Retrieves "ACTIVE" or "PENDING" licenses. If the license is released, the license keeps "ACTIVE".
            - username : (Reuqired if license_source is "fortiflex" or "file_fortiflex" | string | default:"") The username of your FortiFlex account.
            - password : (Reuqired if license_source is "fortiflex" or "file_fortiflex" | string | default:"") The password of your FortiFlex account.
            - config : (Reuqired if license_source is "fortiflex" or "file_fortiflex" | string | default:"") The configuration ID of your FortiFlex configuration (product type should be FortiGate-VM).
        - service_config : (Optional | object) This parameter controls the instance that runs the cloud function. For simplicity, it is recommended to use the default value.
            - max_instance_count : (Optional | number | default:1) The limit on the maximum number of function instances that may coexist at a given time.
            - max_instance_request_concurrency : (Optional | number | default:10) Sets the maximum number of concurrent requests that one cloud function can handle at the same time. Recommended to set it to no less than the maximum number of FGT instances (variable "autoscaler.max_instances").
            - available_cpu : (Optional | string | default:"1") The number of CPUs used in a single container instance.
            - available_memory : (Optional | string | default:"1G") The amount of memory available for a function. Supported units are k, M, G, Mi, Gi. If no unit is supplied the value is interpreted as bytes.
            - timeout_seconds : (Optional | number | default:240) The function execution timeout. Execution is considered failed and can be terminated if the function is not completed at the end of the timeout period.
            - ingress_settings: (Optional | string | default:"ALLOW_ALL") The cloud function accepts what type of ingress traffic. Possible values are: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB.
            - egress_settings: (Optional | string | default:"PRIVATE_RANGES_ONLY") What type of egress traffic will be sent to the VPC connector. Possible values are: VPC_CONNECTOR_EGRESS_SETTINGS_UNSPECIFIED, PRIVATE_RANGES_ONLY, ALL_TRAFFIC.
        - build_service_account_email: (Optional | string | default:"") The email address of the service account used to build the cloud function. This account needs to have role "roles/cloudbuild.builds.builder".
            The <PROJECT_NUMBER>@cloudbuild.gserviceaccount.com will be used if it is not specified.
        - trigger_service_account_email: (Optional | string | default:"") The email address of the service account used to trigger the cloud function. This account needs to have role "roles/run.invoker".
            The default service account will be used if it is not specified.
        - additional_variables : (Optional | map | default: {}) Additional variables used in cloud function. It is used to specify example-specific variables.

    Example:
    ```
    cloud_function = {
      function_ip_range      = "10.1.0.0/28"  # Cloud function needs to have its own CIDR ip range ending with "/28". This IP range cannot be used by other resources.
      license_source         = "file"         # "none", "fortiflex", "file", "file_fortiflex"
      license_file_folder    = "./licenses"
      autoscale_psksecret    = "psksecret"
      logging_level          = "INFO"         # "NONE", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"
      # Specify fortiflex parameters if license_source is "fortiflex" or "file_fortiflex"
      # fortiflex = {
      #   retrieve_mode = "use_active"
      #   username      = "Your fortiflex username"
      #   password      = "Your fortiflex password"
      #   config        = "Your fortiflex configuration ID"
      # }
      # Parameters of google cloud function.
      service_config = {
        max_instance_request_concurrency = 10
        timeout_seconds                  = 360
      }
    }
    ```
  EOF
  validation {
    condition     = can(regex("^port[1-8]$", var.cloud_function.cloud_func_interface))
    error_message = "The cloud_func_interface must be one of 'port1', 'port2', ..., 'port8'."
  }
}

# Bucket
variable "bucket" {
  type = object({
    uniform_bucket_level_access = optional(bool, false)
  })
  default     = {}
  description = <<-EOF
    The bucket used to store license files and cloud function source code.
    The bucket name is generated by the module.

    Options:

        - uniform_bucket_level_access : (Optional | bool | default:false) Whether to enable uniform bucket-level access for the bucket.

    Example:
    ```
    bucket = {
      uniform_bucket_level_access = true
    }
    ```
    EOF
}

# AutoScaler
variable "autoscaler" {
  type = object({
    max_instances   = number
    min_instances   = optional(number, 2)
    cooldown_period = optional(number, 300)
    cpu_utilization = optional(number, 0.9)
    autohealing = optional(object({
      health_check_port   = optional(number, 8008)
      timeout_sec         = optional(number, 5)
      check_interval_sec  = optional(number, 30)
      unhealthy_threshold = optional(number, 10)
      }), {}
    )
    scale_in_control_sec = optional(number, 300)
  })
  description = <<-EOF
    Auto Scaler parameters. This variable controls when to autoscale and the maximum number of instances.
    Options:

        - max_instances     : (Required | number) The maximum number of FGT instances.
        - min_instances     : (Optional | number | default:2) The minimum number of FGT instances.
        - cooldown_period   : (Optional | number | default:300) Specify how long (seconds) it takes for FGT to initialize from boot time until it is ready to serve.
        - cpu_utilization   : (Optional | number | default:0.9) Autoscaling signal. If cpu utilization above this value, google cloud will create new FGT instance.
        - autohealing       : (Optional | Object) Parameters about autohealing. Autohealing recreates VM instances if your application cannot be reached by the health check.
            - health_check_port   : (Optional | number | default:8008) The port used for health checks by autohealing.
            - timeout_sec         : (Optional | number | default:5) How long (in seconds) to wait before claiming a health check failure.
            - check_interval_sec  : (Optional | number | default:30) How often (in seconds) to send a health check.
            - unhealthy_threshold : (Optional | number | default:10) A so-far healthy instance will be marked unhealthy after this many consecutive failures.
        - scale_in_control_sec : (Optional | number | default:300)  When the group scales down, Google Cloud will delete at most one FGT every 'scale_in_control_sec' seconds.

    Example:
    ```
    autoscaler = {
        max_instances   = 10
        min_instances   = 2
        cooldown_period = 300
        cpu_utilization = 0.9
        scale_in_control_sec = 300
    }
    ```
    EOF
}

variable "config_script" {
  type        = string
  default     = ""
  description = "Additional FGT configuration script."
}

variable "config_file" {
  type        = string
  default     = ""
  description = "Additional FGT configuration script file."
}

variable "fmg_integration" {
  type = object({
    ip           = string
    sn           = string
    ums = optional(object({
      autoscale_psksecret = string
      fmg_reg_password    = string
      hb_interval         = optional(number, 30)
      sync_interface      = optional(string, "port1")
      api_key             = optional(string, "")
    }))
  })
  default = null
  description = <<-EOF
  Register FortiGate instance to the FortiManager.

  Options:

    - ip : (Required | string) FortiManager public IP.
    - sn : (Required | string) FortiManager serial number.
    - ums: (Optional | map) Configurations for UMS mode.
      Options for ums:
      - autoscale_psksecret : (Required | string) Password that will used on the auto-scale sync-up.
      - fmg_reg_password : (Required | string) FortiManager Pre-Shared Key for device registration.
      - hb_interval : (Optional | number | default:30) Time between sending heartbeat packets. Increase to reduce false positives. Default: 10.
      - sync_interface : (Optional | string | default:"port1") The interface used to sync with FortiManager. Default: "port1".
      - api_key : (Optional | string | default:"") FortiManager API key that used and required when license_type is 'byol'.
  EOF
}

variable "special_behavior" {
  type = object({
    disable_secret_manager        = optional(bool, false)
    function_creation_wait_sec    = optional(number, 0)
    function_destruction_wait_sec = optional(number, 0)
  })
  default     = {}
  description = <<-EOF
    This variable can specify special behavior to suit various needs.
    Do not use this variable unless instructed by the author.
  EOF
}
