#!/usr/bin/perl -w
use strict;
use Getopt::Std;
require "/ehrms/lowk/scripts/lowlib.pl";

my (%app, %prc, %options) = ();
#
my $r_prc_log_dir = "batch/temp";
my $r_app_log_dir = "server";
my $mat_mnt = "/ehrms";
#
my $prod_mnt = "/phrms";
my $ini_filename = "adpehrms.ini";
my $html_ext = ".htm";
#
my $OFS = ":";			# Output Field Seperator
my $SERVER_P	= 10;		# PAD for formating output string
my $INST_P	= 4;		# PAD for formating output string
my $VER_P	= 7;		# PAD for formating output string
my $URL_P	= -35;		# PAD for formating output string
my $PRC_P	= 10;		# PAD for formating output string

###	SETUP

getopts('apib?', \%options);
if ( $options{'?'} )
	{ usage(); }
my %search					= set_search(\@ARGV, \%options);
my ($product, $server_type)			= override_defaults();
my ($mat_regx, $app_log_regx, $inst_dir_regx)	= set_regx(%search);

###	MAIN

process_materials($mat_mnt, \%app, \%prc);
process_materials($prod_mnt, \%app, \%prc);
my %instances = merge_inst(\%app, \%prc);

if	 ( $options{'i'} )
	{ group_by_instance(%instances); }
elsif	 ( $options{'b'} )
	{ bulk_passwd_change_output(%instances); }
else
	{ group_by_app(%instances); }

###	END	MAIN

sub process_materials()
{
	my ($mat_dir, $app, $prc) = @_;
	unless( -e $mat_dir )
		{ return; }
	opendir(EHRMS, $mat_dir) or die("Could not open $mat_dir  $!");
	while(defined(my $file = readdir(EHRMS)))
	{
		if ( $file =~ $mat_regx )
		{
			my $material = $file;
			my $client = substr($material, 0, 3);
			my $app_log_dir = $mat_dir . "/" . $material . "/" . $r_app_log_dir;
			my $prc_log_dir = $mat_dir . "/" . $material . "/" . $r_prc_log_dir;
			figure_app($app, $material, $app_log_dir);
			figure_prc($prc, $material, $prc_log_dir);
		}
	}
	closedir(EHRMS);
}	#	END process_materials
 

sub figure_app
{
	my ($app, $material, $app_log_dir) = @_;
	my $regx = "";
	my $f_material = "";
	my $client = substr($material, 0, 3);
#
	if	( $product eq "PF" )
	{
		unless ($search{INSTANCE})
			{ $regx=qr/$inst_dir_regx((?:$client)[^\W\d_])$/; }
	}
	else
		{ $regx=qr/^(?:$client)$inst_dir_regx/; }
#
	opendir(APP, $app_log_dir) or die("Could not open $app_log_dir $!");
	APP_INST: while(defined(my $file = readdir(APP)))
	{
		if ( $file =~ m/$regx/ )
		{
			my $instance = $1;
			my $inst_log_dir = $app_log_dir . "/" . $file;
			my ($server, $write_time) = get_recent_log($inst_log_dir, $app_log_regx);
			if ( exists($app->{$instance})  && ( $app->{$instance}{DATE} > $write_time) )
				{ next APP_INST; }
			my $mat_dir = (split(/\//, $inst_log_dir))[1];
			$f_material = "/" . $mat_dir . "/" . $material;
			$app->{$instance}	=
					{
						VERSION	=> $f_material,
						SERVER	=> $server,
						DATE	=> $write_time,
					};
		}
	}
	closedir(APP);
}	#	END figure_app

sub figure_prc
{
	my ($prc, $material, $prc_log_dir) = @_;
	my ($f_material, $prc_log_regx)  = ();
	my $client = substr($material, 0, 3);
#
	opendir(PRC, $prc_log_dir) or die("Could not open $prc_log_dir $!");
	PRC_INST: while(defined(my $file = readdir(PRC)))
	{
		if ( $file =~ m/^(?:$client)[^\d\W_]$/ )
		{
			my $instance = $file;
			if ( exists($search{INSTANCE}) ) 
			{
				if ($search{INSTANCE} ne $instance )
					{ next PRC_INST; }
			}
#
			if ( $product eq "PF" ) 
				{ $prc_log_regx = qr/(.+)ps_(?:$instance)\.log$/; }
			else
				{ $prc_log_regx = qr/(.+)(?:$client)_prc_(?:$instance).log$/; }
#
			my $inst_log_dir = $prc_log_dir . "/" . $file;
			my ($server, $write_time) = get_recent_log($inst_log_dir, $prc_log_regx);
			if ( exists($prc->{$instance}) && ( $prc->{$instance}{DATE} > $write_time) )
				{ next PRC_INST; }
			my $mat_dir = (split(/\//, $inst_log_dir))[1];
			$f_material = "/" . $mat_dir . "/" . $material;
			$prc->{$instance}	=
					{
						VERSION	=> $f_material,
						SERVER	=> $server,
						DATE	=> $write_time,
					};
		}
	}
	closedir(PRC);
}	#	END figure_prc

sub get_recent_log
{
	my ($log_dir, $regx) = @_;
	my $recent_write_time = 0;
	my $recent_server = "";
	opendir(DIR, $log_dir) or die("Could not open $log_dir $!");
	while(defined(my $file = readdir(DIR)))
	{
		if ( $file =~ $regx )
		{
			my $server = $1;
			my $log_file = $log_dir . "/" . $file;
			my $write_time = (stat($log_file))[9] or die("Could not stat $log_file $!");
			if ( $write_time > $recent_write_time)
			{
				$recent_write_time = $write_time;
				$recent_server = $server;
			}
		}
	}
	closedir(DIR);
	if ( $recent_server eq "" )	# can possibly be removed is set correctly initially
		{ $recent_server = "none"; }
	return($recent_server, $recent_write_time);
}	#	END get_recent_log

sub get_maj_ver
{
	my $f_material = shift(@_);
	my $version = (split(/\//, $f_material))[2];
	my $major_version = substr($version,3,1);
	return $major_version;
}	#	END get_maj_ver

sub merge_inst
{
	my ($app, $prc)	= @_;
	my %app		= %$app;
	my %prc		= %$prc;
	my (%instances, $maj_ver)	= ();

	foreach my $instance (keys %app)
	{
		if ( exists($prc{$instance}) )
		{
			if ( $app{$instance}{VERSION} eq $prc{$instance}{VERSION} )
			{
				$maj_ver = get_maj_ver($app{$instance}{VERSION});

				$instances{$instance} =	{
								PRODUCT	=> $product . $maj_ver,
								VERSION	=> $app{$instance}{VERSION},
								APP_SVR	=> $app{$instance}{SERVER},
								PRC_SVR	=> $prc{$instance}{SERVER},
								URL	=> "none",
								DATE	=> "none",
							};
			}
			else
			{
				my $app_svr = $app{$instance}{SERVER}."-".$app{$instance}{VERSION};
				my $prc_svr = $prc{$instance}{SERVER}."-".$prc{$instance}{VERSION};
				$instances{$instance} =	{
								PRODUCT	=> $product . $maj_ver,
								VERSION	=> "mismatch",
								APP_SVR	=> $app_svr,
								PRC_SVR	=> $prc_svr,
								URL	=> "ignore",
								DATE	=> "none",
							};
			}
			delete($prc{$instance});
		}
		else
		{
			$maj_ver = get_maj_ver($app{$instance}{VERSION});
			$instances{$instance} =	{
							PRODUCT	=> $product . $maj_ver,
							VERSION	=> $app{$instance}{VERSION},
							APP_SVR	=> $app{$instance}{SERVER},
							PRC_SVR	=> "none",
							URL	=> "none",
							DATE	=> "none",
						};
		}
		delete($app{$instance});
	}
	foreach my $instance (keys %prc)
	{
		$maj_ver = get_maj_ver($prc{$instance}{VERSION});
		$instances{$instance} =	{
						PRODUCT	=> $product . $maj_ver,
						VERSION	=> $prc{$instance}{VERSION},
						APP_SVR	=> "none",
						PRC_SVR	=> $prc{$instance}{SERVER},
						URL	=> "none",
						DATE	=> "none",
					};
		delete($prc{$instance});
	}
	
	foreach my $instance (keys %instances)
	{
		my $version = $instances{$instance}{VERSION};
		unless ( $version eq "mismatch" )
		{
			$instances{$instance}{URL} = get_url($version, $instance);
			my $ini_db_svr = get_ini_db_svr($version, $instance);
			unless ( $ini_db_svr eq $instances{$instance}{PRC_SVR} )
				{ $instances{$instance}{PRC_SVR} = $ini_db_svr."-".$instances{$instance}{PRC_SVR}; }
		}
	}
	return %instances;
}	#	END merge_inst

sub group_by_app
{
	my %instances = @_;
	my %servers = ();
	foreach my $instance  ( keys(%instances) )
	{
	
		my $version = $instances{$instance}->{VERSION};
		my $server = $instances{$instance}->{APP_SVR};
		my $date = $instances{$instance}->{DATE};
		my $prc_svr = $instances{$instance}->{PRC_SVR};
		my $url = $instances{$instance}->{URL};
		$servers{$server}{$instance} =	{
							VERSION	=> $version,
							DATE	=> $date,
							PRC_SVR	=> $prc_svr,
							URL	=> $url,
						};
	}
	
	
	foreach my $server ( sort(keys(%servers)) )
	{
		foreach my $instance ( keys( %{$servers{$server}}) )
		{
			printf("%${SERVER_P}s\t%${INST_P}s\t%${VER_P}s\t%${URL_P}s\t%${PRC_P}s\n",
				$server,
				$instance,
				$servers{$server}{$instance}->{VERSION},
				$servers{$server}{$instance}->{URL},
				$servers{$server}{$instance}->{PRC_SVR}
				);
		}
	}
}	#	END	group_by_app

sub bulk_passwd_change_output
{
	my %instances = @_;
	foreach my $instance ( sort(keys(%instances)) )
	{
		my $client	= substr($instance, 0, 3);
		my $product	= $instances{$instance}{PRODUCT};
		my $version	= $instances{$instance}{VERSION};
		if ( $version =~ m/mismatch/ )
			{ next;	}
		if ( $instances{$instance}{APP_SVR} =~ m/none/ )
			{ next;	}
		if ( $instances{$instance}{PRC_SVR} =~ m/none/ )
			{ next;	}
		if ( $product =~ m/^PF\d$/ )
		{
			$version =~ s/$mat_mnt/\/mnt\/pf_stag/;
			$version =~ s/$prod_mnt/\/mnt\/pf_prod/;
		}
		else
		{
			$version =~ s/$mat_mnt/\/mnt\/ev3_stag/;
			$version =~ s/$prod_mnt/\/mnt\/ev3_prod/;
		}
		my $ini_file = $version . "/" . $ini_filename;
		printf("%s$OFS%s$OFS%s$OFS%s\n",
			uc($instance),
			$ini_file,
			$client,
			$product
			);
	}
}	#	END	group_by_instance

sub group_by_instance
{
	my %instances = @_;
	foreach my $instance ( sort(keys(%instances)) )
	{
		printf("%${INST_P}s\t%${SERVER_P}s\t%${VER_P}s\t%${URL_P}s\t%${PRC_P}s\n",
			$instance,
			$instances{$instance}->{APP_SVR},
			$instances{$instance}->{VERSION},
			$instances{$instance}->{URL},
			$instances{$instance}->{PRC_SVR}
			);
	}
}	#	END	group_by_instance


sub get_url
{
	my ($version, $instance) = @_;
	my $url = "";
	my $html_file = $version . "/" . "html" . "/" . $instance . $html_ext;
	unless ( -r $html_file )
		{ return "No_($html_ext)_file"; }
	my @HTML = read_file($html_file);
	foreach my $html_line (@HTML)
	{
		if ( $html_line =~ m/(https:\S+):/ )
			{ $url = $1 . "/" . $instance . "/" . $instance . $html_ext; }
	}
	unless(defined($url))
		{ return "No url matched"; }
	return $url;
}

sub get_ini_db_svr
{
	my ($version, $instance) = @_;
	my ($db_svr, $ini_db_svr, $prc_svr_log) = ();
	chop((my $client = $instance));
	my $ini_file = $version . "/" . $ini_filename;
	unless ( -r $ini_file )
		{ $ini_db_svr =  "No adpehrms.ini"; }
	else
	{
		my @ini = read_file($ini_file);
		foreach my $ini_line (@ini)
		{
			if ( $ini_line =~ m/jdbc:oracle:.*@(\w+):\d+:$instance\s*$/i )
				{ $ini_db_svr = $1; }
			unless(defined($ini_db_svr))
				{ $ini_db_svr = "not_in_ini"; }
		}
	}

	return $ini_db_svr;
}

sub set_search
{
	my ($a, $o) = @_;
	my %search = ();
	my @argv	= @$a;
	my %options	= %$o;
	my @flags	= keys(%options);
	
	if ( $#flags > 0 )
	{
		print("Only 1 flag allowed; -a -p -i.\n");
		usage();
	}
	if ( $#argv > 0 )
	{
		print("Only 1 client, instance, server allowed.\n");
		usage();
	}
	if ( $#argv == 0 )
	{
		my $value = shift(@argv);
		if ( $options{a} || $options{p} )
			{ $search{SERVER}=$value; }
		else
		{
			my $length = length($value);
			if ( ($length > 4) || ($length < 3) )
			{
				print("Only 4 char instance IIII or 3 char client CCC allowed.\n");
				usage();
			}
			elsif ( $length == 4 )
				{ $search{INSTANCE} = $value; }
			$search{CLIENT} = substr($value, 0, 3);
		}
	}
	return %search;
}	#	END	set_search

sub usage
{
	print("\n$0 [ -a [app_server] | -p [prc_server] | -i [instance|client] ] | [instance|client]\n\n");
	print("\t -a [server_name]\tGroup by app server and restrict to specific server.\n");
	print("\t -p [server_name]\tGroup by prc server and restrict to specific server.\tNOT IMPLEMENTED\n");
	print("\t -i [IIII|CCC]   \tGroup by instance or client and restrict.\n");
	print("\t [IIII|CCC]      \tRestrict to specific instance or client.\n");
	print("\t -b              \tGenerate output for Bulk Password Utility\n");
	print("\n");
	exit();
}

sub set_regx
{
	my %search = @_;
	my $mat_regx		= qr/^\w\w\w\d\d\d[^\W\d_]$/;		# can limit to specific client
	my $app_log_regx	= qr/^(\w+)HRServer\.log$/;		# can limit to specific server
	my $inst_dir_regx	= qr/_(\w\w\w\w)_svr$/;		# can limit to specific instance
	
	if ( $product eq "PF" )
	{
		$mat_regx = qr/^\w\w\w\d\d\d[^\W\d_]?$/;	# final char optional
		$inst_dir_regx	= qr/^as_/;		# can limit to specific instance
		$app_log_regx	= qr/^(\w+)PFServer\.log$/;
	}
	
	if ( $search{INSTANCE} )
	{
		if ( $product eq "PF" )
		{ $inst_dir_regx = qr/^as_($search{INSTANCE})$/; }
		else
		{ $inst_dir_regx = qr/_($search{INSTANCE})_svr$/; }
	}
	if ( $search{CLIENT} )
	{
		if ( $product eq "PF" )
		{ $mat_regx = qr/^$search{CLIENT}\d\d\d[^\W\d_]?$/; }
		else
		{ $mat_regx = qr/^$search{CLIENT}\d\d\d[^\W\d_]$/; }
	}
	if ( $search{SERVER} )
	{
		if ( $product eq "PF" )
		{ $app_log_regx = qr/^($search{SERVER})PFServer\.log$/; }
		else
		{ $app_log_regx = qr/^($search{SERVER})HRServer\.log$/; }
	}

	return ($mat_regx, $app_log_regx, $inst_dir_regx);
}

sub override_defaults
{
	my $product	= "EV";
	my $server_type	= "unk";
	my $hostname = `/usr/bin/uname -n`;
#
	if ( $hostname =~ m/pf/ )
	{
		$product	= "PF";
		$prod_mnt	= "/pf_prod";
		$ini_filename	= "payforce.ini";
		$html_ext	= ".html";
	}
#
	if	( $hostname =~ m/ap/ )
	{ $server_type = "ap"; }
	elsif	( $hostname =~ m/db/ )
	{ $server_type = "db"; }

	return ($product, $server_type);
}	#	END override_defaults
