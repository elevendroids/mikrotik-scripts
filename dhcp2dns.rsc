###
# Script entry point
#
# Expected environment variables - set internally when calling the lease script:
# leaseBound         1 = lease bound, 0 = lease removed
# leaseServerName    Name of DHCP server
# leaseActIP         IP address of DHCP client
# leaseActMAC        MAC address of DHCP client
# lease-hostname     Host name provided by the DHCP client
# lease-options      DHCP options provided by the client
###
:local leaseHostName $"lease-hostname"
:local leaseOptions $"lease-options"
# DNS TTL to set for DNS entries
:local dnsttl "00:15:00"

### Utility functions ###

# Generates a host name from an IP address, ie:
# "192.168.1.10" -> "192-168-1-10"
# Used as a replacement for missing host names
# param: ip
:local ip2Host do={
  :local ipNum [ :tonum [ :toip $ip ] ]
  :return ((($ipNum >> 24) & 255) . "-" . (($ipNum >> 16) & 255) . "-" . (($ipNum >> 8) & 255) . "-" . ($ipNum & 255))
}

# Sanitizes a host name: length <= 63, allowed chars a-z,0-9,-
# param: name
:local mapHostName do={
  :local allowedChars "abcdefghijklmnopqrstuvwxyz0123456789-"
  :local numChars [ :len $name ]
  :if ($numChars > 63) do={ :set numChars 63 }
  :local result ""

  :for i from=0 to=($numChars - 1) do={
    :local char [ :pick $name $i ]
    :if ([ :find $allowedChars $char ] < 0) do={ :set char "-" }
    :set result ($result . $char)
  }
  :return $result
}

# Converts a host name to all-lower-case
# param: entry
:local lowerCase do={
  :local lower "abcdefghijklmnopqrstuvwxyz"
  :local upper "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  :local result ""
  :for i from=0 to=([ :len $entry ] - 1) do={
    :local char [ :pick $entry $i ]
    :local pos [ :find $upper $char ]
    :if ($pos > -1) do={ :set char [ :pick $lower $pos ] }
    :set result ($result . $char)
  }
  :return $result
}

###

:local token "$leaseServerName-$leaseActMAC"
:local LogPrefix "DHCP2DNS ($leaseServerName) [$leaseActMAC]"

:if ([ :len $leaseActIP ] <= 0) do={
  :log error "$LogPrefix: empty lease address"
  :error "empty lease address"
}

:if ($leaseBound = 1) do={
  /ip dhcp-server network
  :local domain [ get [ :pick [ find $leaseActIP in address ] 0 ] domain ]
  :local hostname $leaseHostName

  :if ([ :len $hostname ] > 0) do={
    :set hostname [ $lowerCase entry=$hostname ]
    :set hostname [ $mapHostName name=$hostname ]
  } else={
    :set hostname [ $ip2Host ip=$leaseActIP ]
  }

  :if ([ :len $domain ] <= 0) do={
    :log warning "$LogPrefix: Empty domainname for '$leaseActIP', cannot create static DNS name"
    :error "Empty domainname for '$leaseActIP'"
  }

  :local fqdn ($hostname . "." .  $domain)

  /ip dns static
  :local entry [ find name=$fqdn ]
  :if ( $entry ) do={
    :if ([ get $entry comment ] = $token) do={
      :log warning "$LogPrefix: Updating existing entry for $fqdn"
      set $entry address=$leaseActIP ttl=$dnsttl comment=$token
    } else={
      :log warning "$LogPrefix: Conflicting entry for $fqdn already exists, not updating"
    }
  } else={
    :local placeholderComment "--- $leaseServerName dhcp2dns above ---"
    :if ( [ :len [ find comment=$placeholderComment ] ] = 0 ) do={
      add comment=$placeholderComment name=- type=NXDOMAIN disabled=yes
    }
    :local placeholder [ find where comment=$placeholderComment ]

    :log info "$LogPrefix: Adding entry for $fqdn"
    add address=$leaseActIP name=$fqdn ttl=$dnsttl comment=$token place-before=$placeholder
  }
} else={
  /ip dns static remove [ find comment=$token ]
}
