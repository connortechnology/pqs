package openprint::Map;

use strict;

use Apache::Request;    # instead of CGI, it's MUCH faster, and does nice things.
use Apache::Log;
use	Image::Magick;

use openprint ();
use Ekahau;

use constant DEFAULT_DEVICE_CHECK => 10;
use constant DEFAULT_NUM_GUESSES => 5;
use constant DEFAULT_GUESS_THRESHOLD => .10;

use vars qw(%ekopts %devices %locations @areas );
$ekopts{PeerAddr} = 'ekahauserver';
my $device_check_timeout = DEFAULT_DEVICE_CHECK;
my $guess_threshold = DEFAULT_GUESS_THRESHOLD;
$ekopts{Timeout} = $device_check_timeout;
$ekopts{LicenseFile} = '/srv/Backups/ekahau/license/EkahauSDK3.1/license.xml';
my $ek;

my %floor;

sub handler {
	# this module just generates barcodes
	my $request = shift;
	my $r = Apache::Request->new( $request );
	$r->log->debug("Starting Ekahau Image Maps");
	$r->content_type('image/png');
	if ( ! $r->param('skid_id') ) {
		# Make an image with an error written on it!
		$r->log->error("No skid id supplied!");
		return Apache::OK;
	} # end if
	$r->log->debug("Connecting to Ekahau");
	$ek = Ekahau->new(%ekopts) if ! $ek;
	$r->log->debug("Getting Map");
	my $map_image = $ek->get_map_image();
	if ( ! $map_image ) {
		$r->log->debug($$ek{_lasterror});
	} else {
		$r->log->debug("Got map: " . $map_image->map_size() );
		print $map_image->map_image();
	} # end if
	#my $image=Image::Magick->new(magick=>'png');
	#$image->BlobToImage($blob);
	#$blob = $image->ImageToBlob();

	return Apache::OK;
} # end sub handler


sub jsrs_find {
my ( $r, $log, $dbh, $variable ) = @_;
	my %where = find( $log, $ENV{'REMOTE_ADDR'} );
	return "Location~$where{map}.$where{area} ($where{x}x$where{y})";
}


sub find {
	my ( $log, $ip ) = @_;

	my %where;

	my $loc_params = {
	};
	$ek = Ekahau->new(%ekopts) if ! $ek;
	if ( ! $ek ) {
		$log->error("Couldn't create Ekahau object: $!\n");
		return;
	} # end if
	if ( ! @areas ) {
		# Load all areas
		#@areas = $ek->get_all_areas()->get_all();

	} # end if

	$log->debug("EKAHAU: Looking for $ip");
	my %hash = ( 'NETWORK.IP-ADDRESS' => $ip );
	foreach my $dev ( $ek->request_device_list(\%hash) ) {
		if ( ! $devices{$ip} ) {
			$devices{$ip} = $dev;
			$ek->start_area_track($loc_params, $dev);
			$ek->start_location_track($loc_params, $dev);
		} # end if
	} # end foreach

	# Loops until we get an area response
	while ( 1 ) {
		my $loc = $ek->next_track(Timeout => $device_check_timeout );
		if ( ! $loc ) {
			$log->error("Unable to locate device with ip $ip");
			return;
		} # end if
		my $dev = $loc->{args}[0];

		if ( $loc->type eq 'AreaEstimate') {
			$log->debug("Area Estimate" . $loc->get_prop('name') );
			my $where = $loc->get_prop('name');
			if (!$where or $where eq 'null') { $where = 'Unknown' }
			$locations{$dev}{area} = $where;

			my($coord,$relcoord)=("","");

			$locations{$dev}{map} = get_floor($log,$ek,$loc->get_prop('contextId'));
			$where = join(".", $locations{$dev}{map}, $where);

			if (defined($locations{$dev}{x}) and defined($locations{$dev}{y})) {
				$coord = " COORDINATES $locations{$dev}{x},$locations{$dev}{y}";
				my $poly = $loc->get_prop('polygon');
				if ($poly and $poly ne 'null') {
					my($all_x,$all_y) = split(/\&/,$poly);
					my $upper_y = min(split(/;/,$all_y));
					my $leftmost_x = min(split(/;/,$all_y));
					$relcoord = sprintf(" RELCOORD %.2f,%.2f",
							($locations{$dev}{x}-$leftmost_x),
							($locations{$dev}{y}-$upper_y));
				}
			}
			my $ormaybe = "";
			my @alternate = $loc->get_all;
			shift @alternate;
			foreach my $room (@alternate) {
			$log->debug("Alternate: " . $room->get_prop('name') );
				if ($room->get_prop('probability') >= $guess_threshold) {
					$ormaybe .= " ORMAYBE_FROM " .
						join(".",get_floor($log, $ek,$room->get_prop('contextId')),
								$room->get_prop('name'));
					$ormaybe .= " ORMAYBE_CONFIDENCE ".$room->get_prop('probability');
				}
			}

			$log->debug( "ISEE Ekahau.$ip FROM $where$coord$relcoord AT ".time." CONFIDENCE ".$loc->{params}{probability}."$ormaybe\n" );
			if ( $locations{$dev}{area} ne 'Unknown' ) {
			last;
			}


		} elsif ( $loc->type eq 'LocationEstimate') {
			$log->debug("Location Estimate".join(',',
				 join('x',$loc->get_prop('accurateX'), $loc->get_prop('accurateY') ),
				 join('x', $loc->get_prop('latestX'), $loc->get_prop('latestY') )
				 ) );
			$locations{$dev}{x} = $loc->get_prop('accurateX') ? $loc->get_prop('accurateX') : $loc->get_prop('latestX');
			$locations{$dev}{y} = $loc->get_prop('accurateY') ? $loc->get_prop('accurateY') : $loc->get_prop('latestY');
		} elsif ($loc->error) {
			$log->error( "errorMessage=".$loc->error_msg.", errorCode=".$loc->error_code.", errorLevel=".$loc->error_level );
		} else {
			$log->error("Unknown location?" . $loc->type );

		} # end if
	} # end while ( 1) 
	$where{x} = $locations{$devices{$ip}}{x};
	$where{y} = $locations{$devices{$ip}}{y};
	$where{area} = $locations{$devices{$ip}}{area};
	$where{map} = $locations{$devices{$ip}}{map};
	return %where;
} # end sub find

sub get_floor {
	my( $log, $ek,$ctx_id )=@_;
	
	if( ! ($ek and $ctx_id) ) {
		$log->error("Usage: get_floor(ekahau_obj, context_id)" );
		return;
	} # end if
	if (!$floor{$ctx_id}) {
		if (my $ctx = $ek->get_location_context($ctx_id)) {
			$floor{$ctx_id}=$ctx->get_prop('address');
			$floor{$ctx_id} =~ s|/|.|g;
		}
	}
	$floor{$ctx_id};
}

sub min {
    my $min = shift;
	while(@_) {
		my $v = shift;
		if ($v < $min) {
			$min = $v;
		}
	}
	$min;
}

sub map {
	my ( $ek, $location_id ) = @_;
	
} # end sub map

1;

__END__
