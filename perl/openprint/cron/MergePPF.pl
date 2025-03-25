#!/usr/bin/perl
use lib qw( /etc/apache2/lib/perl );
use Linux::Inotify2;

use strict;

require sets;
require sql;
require logger;
require configuration;
require openprint::CIP3_PPF;
require openprint::Project;
require openprint::service;
use openprint ();
use MIME::Base64;

use vars qw( $log $dbh %config );

*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

$log = logger->new();
$log->{level} = 'warn';

my $source_path = $ARGV[0];
my $dest_path = $ARGV[1];
my $db_host = $ARGV[2];
my $db_name = $ARGV[3];
my $db_user = $ARGV[4];
my $db_pass = $ARGV[5];
$db_user = $db_name if ! $db_user;
$db_pass = $db_name if ! $db_pass;

my $inotify = new Linux::Inotify2;
if ( 0 and $inotify and $inotify->watch( $source_path, IN_CREATE ) ) {
  while () {
    my @events = $inotify->read;
    if ( ! @events ) {
      print "Read error";
    } # end if
    printf "mask\t%d\n", $_->mask foreach @events;
  } # end while
} else {
  # Command Line Params: 
  # 1. Hot Folder to monitor
  # 2.  Dest HotFolder
  my @filenames;
  if ( opendir DIRHANDLE, $source_path ) {
    @filenames = readdir DIRHANDLE;
    closedir DIRHANDLE;
  } else {
    die "Unable to open $source_path\n";
  } # end if

  foreach my $file ( @filenames ) {
    # Will ignore ., .., any hidden file
    next if $file =~ /^\./; 
    if ( $file =~ /(.*)B\.(ppf)$/i ) {
      my $file_base = $1;
      my $extension = $2;
      my  $out_base = $file_base;
      $out_base =~ s/\./_/g;

      if ( sets::isin( $file_base.'A.'.$extension, @filenames ) ) {
        if ( ! open ( FH, '< ' . $source_path.'/'.$file_base.'B.'.$extension ) ) {
          print "Error opening " . $source_path.'/'.$file_base."B.$extension\n" ;
          next;
        } # end if

        my @Back;
        my $back_flag = 0;  
        while ( <FH> ) {
          $back_flag = 1 if ( $_ =~ /CIP3BeginBack/ );
          push @Back, $_ if ( $back_flag );
          last if $_ =~ /CIPEndBack/;
        } # end while
        close( FH );
        if ( ! @Back ) {
          print "No Back found in B file!\n";
          rename $source_path.'/'.$file_base.'B.'.$extension, $source_path.'/'.$file_base.'E.'.$extension;
          next;
        } # end if
        my $A;
        if ( ! open( $A, '< '.$source_path.'/'.$file_base.'A.'.$extension ) ) {
          print "Error opening " . $source_path.'/'.$file_base."A.$extension\n" ;
          next;
        } # end if
        if ( ! open( M, '> '.$dest_path.'/'.$out_base.'M.'.$extension ) ) {
          print "Error opening " . $dest_path.'/'.$file_base."M.$extension\n" ;
          next;
        } # end if
        my $fileA = $file_base.'A';
        my $fileM = $file_base.'M';

        my ( $docket, $ppo, $name, $sig, $side ) = $file =~ /(\d+)(\w\w)?_?(.*?)S?g?(\d+)S?d?\.?(\w)\.PPF/i;
        my $data;
  #print "File: $file Docket $docket, Operattor: $ppo, Name: $name, Sig: $sig, $side\n";
        $sig = 0 if ! $sig;
        while ( <$A> ) {
          my $line = $_;
          next if $line =~ /^CIP3EndSheet/;
          $line =~ s/$fileA/$fileM/g;
          if ( $line =~ /^\/CIP3AdmSheetName \(Sheet (\d*)\) def/ ) {
            $line = sprintf("/CIP3AdmSheetName (Sig#%dSheet#%d) def\r\n", 1*$sig, $1 );
          } # end if

          if ( $line =~ /CIP3EndOfFile/ ) {
            foreach ( @Back ) {
              last if $_ =~ /^CIP3EndOfFile/;
              print M $_;
              $data .= $_;
            } # end foreach
          } # end if
          print M $line;
          $data .= $line;
        } # end while
        close $A;
        close M;
        unlink $source_path.'/'.$file_base.'A.'.$extension;
        unlink $source_path.'/'.$file_base.'B.'.$extension;

        if ( $docket ) {
          $dbh = sql::open_sql( $log,
              'host'      => $db_host,
              'database'  => $db_name,
              'driver'    => 'Pg',
              'login'     => $db_user,
              'password'  => $db_pass,
              ) if ! ( $dbh and $dbh->ping() );
          die 'Error opening db' if ! $dbh;

          configuration::init_cache( $log, $dbh );
          foreach my $PPF (openprint::CIP3_PPF->find( docket=>$docket, signature=>$sig, side=>$side)) {
            $PPF->delete();
          } # end foreach
          foreach my $Project ( openprint::Project->find(docket=>$docket) ) {
            my $services = $Project->services();

            my $found = 0;
            foreach my $ss_id ( $Project->signatures() ) {
              my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
              if ( $$services{'Signature'} ) {
                if ( $sig == $$sig_specs{'SignatureIndex'} ) {
                  $found = 1;
                  last;
                } # end if
              } elsif ( $sig == $$sig_specs{'SignatureIndex'}+1 ) {
                $found = 1;
                last;
              } # end if
            } # end foreach sig
            if ( ! $found ) {
              $Project->add_signature( $sig, 'uncalculated', {  
                  txtSignatureType => 'Interior Pages',
                  txtServiceDescription  => 'Interior Pages',
                  } );
            } # end if
          } # end foreach Project
          my $PPF = new openprint::CIP3_PPF();
          $_ = $PPF->save({
              docket      =>  $docket,
              signature   =>  $sig,
              side        =>  'M',
              data        =>  encode_base64($data),
              data_length =>  length $data,
              });
          $log->error($_) if $_;
          $dbh->disconnect() if $dbh;
        } else {
          $log->error("$docket not found for $file_base");
        } # end if docket

      } # end if
    } # end if
  } # end foreach
} # end if inotify
1;
__END__
