# Future development

### Webhook endpoints

I'm unsure if I want this. Webhooks are definitely useful, but I can get that
functionality from other services, like Jenkins.

Perhaps a separate tool that acts as a shim would be good.

### Support updating module branches separately

This is useful if we can get a webhook for a module branch, or if we happen
to know that it is updated more frequently than other things and thus should
be checked more frequently.

### Manage multiple masters

1. Separate updates into three steps:

   1. _Prepare_: determine what repos and refs to update
   2. _Stage_: update repos an check out the needed shas
   3. _Activate_: make the ref changes

   _Prepare_ will be run on the armature master (the Puppet MoM, presumably)
   and will generate a data object to pass to other nodes for the _stage_ and
   _activate_ steps.

   We have to be careful that a poorly timed garbage collect doesn't wipe out
   our work. That means keeping a process running to hold a lock, or adding some
   sort of expiring lock on staged refs.

2. Add interface for passing data between nodes

   * HTTP can be proxied through NGINX for encryption and access control.

   * SSH provides encryption and access control natively.
