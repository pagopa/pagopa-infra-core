A simple application, written in python, that provides a REST API for editing icinga business processes

this api allows the caller to edit the business process config file identified by <bp>.conf, adding a section dedicated to <target>.

this api should add a section to the business process config file, with the following structure:

- <target>_<domain> = <host>;<name> & <host>;<name>

where every pair of <target>_<domain> is unique, and contains the concatenation using the `&` operator of all the `<host>;<name>` pairs provided in the request body for the given domain.

the section must be identified in the <bp>.conf file by the following comment:
# begin <target> section
# end <target> section

written respectively before and after the section.

Upon subsequent invocation for the same target, the whole already written sectin should be replaced with the new one.


The bp.conf file is located in `/etc/icingaweb2/modules/businessprocess/processes/`, accept it as config value  

API endpoint:

```POST /business-process/<bp>/block/<target>```
body:
```
{
  "blocks": [
    {
      "domain": string,
      "name": string
    }
  ],
  "host": string
}
```
response:
only the http status code, 200 for success, 400 for bad request, 500 for internal server error. and a message explaining the error, in json format
```
{
"message": string
}
```
