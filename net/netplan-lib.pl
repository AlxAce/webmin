# Networking functions for Ubuntu 17+, which uses Netplan by default

$netplan_dir = "/etc/netplan";

do 'linux-lib.pl';

sub boot_interface
{
my @rv;
foreach my $f (glob("$netplan_dir/*.yaml")) {
	my $yaml = &read_yaml_file($f);
	next if (!$yaml || !$yaml->{'network'});
	my $ens = $yaml->{'network'}->{'ethernets'};
	next if (!$ens);
	foreach my $e (@{$ens->{'members'}}) {
		my $cfg = { 'name' => $e->{'name'},
			    'fullname' => $e->{'name'},
			    'up' => 1 };
		my ($dhcp) = grep { $_->{'name'} eq 'dhcp4' }
				  @{$e->{'members'}};
		if (&is_true_value($dhcp)) {
			$cfg->{'dhcp'} = 1;
			}

		# IPv4 and v6 addresses
		my ($addresses) = grep { $_->{'name'} eq 'addresses' }
				       @{$e->{'members'}};
		my @addrs;
		my @addrs6;
		if ($addresses) {
			@addrs = grep { !&check_ip6address($_) }
				      @{$addresses->{'value'}};
			@addrs6 = grep { &check_ip6address($_) }
				       @{$addresses->{'value'}};
			my $a = shift(@addrs);
			($cfg->{'address'}, $cfg->{'netmask'}) =
				&split_addr_netmask($a);
			}
		foreach my $a6 (@addrs6) {
			if ($a6 =~ /^(\S+)\/(\d+)$/) {
				push(@{$cfg->{'address6'}}, $1);
				push(@{$cfg->{'netmask6'}}, $2);
				}
			else {
				push(@{$cfg->{'address6'}}, $a6);
				push(@{$cfg->{'netmask6'}}, 64);
				}
			}

		# IPv4 and v4 gateways
		my ($gateway4) = grep { $_->{'name'} eq 'gateway4' }
				      @{$e->{'members'}};
		if ($gateway4) {
			$cfg->{'gateway'} = $gateway4->{'value'};
			}
		my ($gateway6) = grep { $_->{'name'} eq 'gateway6' }
				      @{$e->{'members'}};
		if ($gateway6) {
			$cfg->{'gateway6'} = $gateway6->{'value'};
			}
		push(@rv, $cfg);

		# Add IPv4 alias interfaces
		foreach my $aa (@addrs) {
			# XXX
			}
		}
	}
return @rv;
}

# can_edit(what)
# Can some boot-time interface parameter be edited?
sub can_edit
{
return $_[0];
}

# valid_boot_address(address)
# Is some address valid for a bootup interface
sub valid_boot_address
{
return &check_ipaddress_any($_[0]);
}

# get_hostname()
sub get_hostname
{
local $hn = &read_file_contents("/etc/hostname");
$hn =~ s/\r|\n//g;
if ($hn) {
	return $hn;
	}
return &get_system_hostname(1);
}

# save_hostname(name)
sub save_hostname
{
local (%conf, $f);
&system_logged("hostname $_[0] >/dev/null 2>&1");
foreach $f ("/etc/hostname", "/etc/HOSTNAME", "/etc/mailname") {
	if (-r $f) {
		&open_lock_tempfile(HOST, ">$f");
		&print_tempfile(HOST, $_[0],"\n");
		&close_tempfile(HOST);
		}
	}
undef(@main::get_system_hostname);      # clear cache
}

# get_domainname()
sub get_domainname
{
local $d;
&execute_command("domainname", undef, \$d, undef);
chop($d);
return $d;
}

# save_domainname(domain)
sub save_domainname
{
local %conf;
&execute_command("domainname ".quotemeta($_[0]));
}

sub routing_config_files
{
return ( $netplan_dir, $sysctl_config );
}

sub network_config_files
{
return ( "/etc/hostname", "/etc/HOSTNAME", "/etc/mailname" );
}

# read_yaml_file(file)
# Converts a YAML file into a nested hash ref
sub read_yaml_file
{
my ($file) = @_;
my $lref = &read_file_lines($file, 1);
my $lnum = 0;
my $rv = [ ];
my $parent = { 'members' => $rv,
	       'indent' => -1 };
foreach my $origl (@$lref) {
	my $l = $origl;
	$l =~ s/#.*$//;
	if ($l =~ /^(\s*)(\S+):\s*(.*)/) {
		# Value line
		my $i = length($1);
		my $dir = { 'indent' => $1,
			    'name' => $2,
			    'value' => $3,
			  };
		if ($dir->{'value'} =~ /^\[(.*)\]$/) {
			$dir->{'value'} = [ split(/,/, $1) ];
			}
		push(@{$parent->{'members'}}, $dir);
		}
	elsif ($l =~ /^(\s*)(\S+):\s*$/) {
		# Section header line
		my $i = length($1);
		my $dir = { 'indent' => $1,
			    'name' => $2,
			    'members' => [ ],
			  };
		if ($i > $parent->{'indent'}) {
			# Start of a sub-section inside the current directive
			push(@{$parent->{'members'}}, $dir);
			$dir->{'parent'} = $parent;
			$parent = $dir;
			}
		else {
			# Pop up a level (or more)
			while($i <= $parent->{'indent'}) {
				$parent = $parent->{'parent'};
				}
			}
		}
	}
return $rv;
}

# split_addr_netmask(addr-string)
# Splits a string like 1.2.3.4/24 into an address and netmask
sub split_addr_netmask
{
my ($a) = @_;
if ($a =~ /^([0-9\.]+)\/(\d+)$/) {
	return ($1, &prefix_to_mask($2));
	}
elsif ($a =~ /^([0-9\.]+)\/([0-9\.]+)$/) {
	return ($1, $2);
	}
else {
	return $a;
	}
}

sub is_true_value
{
my ($dir) = @_;
return $dir && $dir->{'value'} =~ /true|yes|1/i;
}

1;