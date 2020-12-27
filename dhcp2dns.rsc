# DNS TTL to set for DNS entries
:local dnsttl "00:15:00";

###
# Script entry point
#
# Expected environment variables:
# leaseBound         1 = lease bound, 0 = lease removed
# leaseServerName    Name of DHCP server
# leaseActIP         IP address of DHCP client
#leaseActMAC      MAC address of DHCP client
###

# "a.b.c.d" -> "a-b-c-d" for IP addresses used as replacement for missing host names
:local ip2Host do=\
{
  :local outStr
  :for i from=0 to=([:len $inStr] - 1) do=\
  {
    :local tmp [:pick $inStr $i];
    :if ($tmp =".") do=\
    {
      :set tmp "-"
    }
    :set outStr ($outStr . $tmp)
  }
  :return $outStr
}

:local mapHostName do={
# param: name
# max length = 63
# allowed chars a-z,0-9,-
  :local allowedChars "abcdefghijklmnopqrstuvwxyz0123456789-";
  :local numChars [:len $name];
  :if ($numChars > 63) do={:set numChars 63};
  :local result "";

  :for i from=0 to=($numChars - 1) do={
    :local char [:pick $name $i];
    :if ([:find $allowedChars $char] < 0) do={:set char "-"};
    :set result ($result . $char);
  }
  :return $result;
}

:local lowerCase do={
# param: entry
  :local lower "abcdefghijklmnopqrstuvwxyz";
  :local upper "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  :local result "";
  :for i from=0 to=([:len $entry] - 1) do={
    :local char [:pick $entry $i];
    :local pos [:find $upper $char];
    :if ($pos > -1) do={:set char [:pick $lower $pos]};
    :set result ($result . $char);
  }
  :return $result;
}

:local token "$leaseServerName-$leaseActMAC";
:local LogPrefix "DHCP2DNS ($leaseServerName)"

:if ( [ :len $leaseActIP ] <= 0 ) do=\
{
  :log error "$LogPrefix: empty lease address"
  :error "empty lease address"
}

:if ( $leaseBound = 1 ) do=\
{
  # new DHCP lease added
  /ip dhcp-server
  #:local dnsttl [ get [ find name=$leaseServerName ] lease-time ]
  network
  :local domain [ get [ find $leaseActIP in address ] domain ]
  #:log info "$LogPrefix: DNS domain is $domain"

  :local hostname [/ip dhcp-server lease get [:pick [find mac-address=$leaseActMAC and server=$leaseServerName] 0] value-name=host-name]
  #:log info "$LogPrefix: DHCP hostname is $hostname"

 #Hostname cleanup
  :if ( [ :len $hostname ] <= 0 ) do=\
  {
    :set hostname [ $ip2Host inStr=$leaseActIP ]
    :log info "$LogPrefix: Empty hostname for '$leaseActIP', using generated host name '$hostname'"
  }
  :set hostname [$lowerCase entry=$hostname]
  :set hostname [$mapHostName name=$hostname]
  #:log info "$LogPrefix: Clean hostname for FQDN is $hostname";

  :if ( [ :len $domain ] <= 0 ) do=\
  {
    :log warning "$LogPrefix: Empty domainname for '$leaseActIP', cannot create static DNS name"
    :error "Empty domainname for '$leaseActIP'"
  }

  :local fqdn ($hostname . "." .  $domain)
  #:log info "$LogPrefix: FQDN for DNS is $fqdn"

    :if ([/ip dhcp-server lease get [:pick [find mac-address=$leaseActMAC and server=$leaseServerName] 0] ]) do={
      # :log info message="$LogPrefix: $leaseActMAC -> $hostname"
      :do {
        /ip dns static add address=$leaseActIP name=$fqdn ttl=$dnsttl comment=$token;
      } on-error={:log error message="$LogPrefix: Failure during dns registration of $fqdn with $leaseActIP"}
    }

} else={
# DHCP lease removed
  /ip dns static remove [find comment=$token];
}
