-- Config options Kong accepts for this plugin.
return {
  name = "x-environment-validator",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          {
            allowed_environments = {
              type = "string",
              default = "DEV,UAT,PROD",
              description = "Comma-separated list of allowed environment values"
            }
          },
          {
            header_name = {
              type = "string",
              default = "x-environment",
              description = "Name of the header to validate"
            }
          }
        }
      }
    }
  }
}
