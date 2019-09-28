local typedefs = require "kong.db.schema.typedefs"

return {
  name = "request-firewall",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { path_pattern = { type = "string" } },
        { content_type = { type = "string" } },
        { path = {
          type = "map",
          keys = {
            type = "string"
          },
          values = {
            type = "record",
            fields = {
              { type = { type = "string", required = false, default = "string" } },
              { is_array = { type = "number", required = false, default = 0 } },
              { required = { type = "boolean", required = false, default = false } },
              { precision = { type = "number", required = false } },
              { positive = { type = "boolean", required = false } },
              { min = { type = "number", required = false } },
              { max = { type = "number", required = false } },
              { match = { type = "string", required = false } },
              { not_match = { type = "string", required = false } },
              { enum = { type = "array", required = false, elements = { type = "string" } } }
            }
          }
        }},
        { query = {
          type = "map",
          keys = {
            type = "string"
          },
          values = {
            type = "record",
            fields = {
              { type = { type = "string", required = false, default = "string" } },
              { is_array = { type = "number", required = false, default = 0 } },
              { required = { type = "boolean", required = false, default = false } },
              { precision = { type = "number", required = false } },
              { positive = { type = "boolean", required = false } },
              { min = { type = "number", required = false } },
              { max = { type = "number", required = false } },
              { match = { type = "string", required = false } },
              { not_match = { type = "string", required = false } },
              { enum = { type = "array", required = false, elements = { type = "string" } } }
            }
          }
        }},
        { body = {
          type = "map",
          keys = {
            type = "string"
          },
          values = {
            type = "record",
            fields = {
              { type = { type = "string", required = false, default = "string" } },
              { is_array = { type = "number", required = false, default = 0 } },
              { required = { type = "boolean", required = false, default = false } },
              { precision = { type = "number", required = false } },
              { positive = { type = "boolean", required = false } },
              { min = { type = "number", required = false } },
              { max = { type = "number", required = false } },
              { match = { type = "string", required = false } },
              { not_match = { type = "string", required = false } },
              { enum = { type = "array", required = false, elements = { type = "string" } } }
            }
          }
        }},
        { custom_classes = {
          type = "map",
          keys = {
            -- this the class name
            type = "string"
          },
          values = {
            -- this is the class definition, itself is also a map
            type = "map",
            keys = {
              -- this is the field name
              type = "string"
            },
            values = {
              type = "record",
              fields = {
                { type = { type = "string", required = false, default = "string" } },
                { is_array = { type = "number", required = false, default = 0 } },
                { required = { type = "boolean", required = false, default = false } },
                { precision = { type = "number", required = false } },
                { positive = { type = "boolean", required = false } },
                { min = { type = "number", required = false } },
                { max = { type = "number", required = false } },
                { match = { type = "string", required = false } },
                { not_match = { type = "string", required = false } },
                { enum = { type = "array", required = false, elements = { type = "string" } } }
              }
            }
          }
        }},
      }
    }}
  }
}