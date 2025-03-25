use strict;
package openprint::License;
our @ISA = qw(openprint::Object);

require openprint::License_Host;
require openprint::Software;
require File::Slurp;
require JSON;
use Crypt::OpenSSL::Random;
use Crypt::OpenSSL::RSA;
#use Crypt::RSA;
use Digest::SHA qw(sha256_hex);
use MIME::Base64;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );
$debug = 1;
$table = 'licenses';
$serial='licenses_id_seq';
%fields = (
		id						=>	'id',
    company_id    =>  'company_id',
    site_id       =>  'site_id',
    hash          =>  'hash',
		serialkey			=>	'serialkey',
		max_uses			=>	'max_uses',
		purchased_on	=>	'purchased_on',
		expires_on		=>	'expires_on',
		software_id		=>	'software_id',
		software			=>	undef,
		comment       =>	'comment',
		created_on		=>	'created_on',
		updated_on		=>	'updated_on',
    features_json      =>  'features_json', # json encoded
    features => undef,
		);
%find_fields = (
		host_id	=>	'id IN (SELECT license_id FROM license_hosts where host_id=?)',
);
%transforms = (
		serialkey	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
		comment		=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
		);
%defaults = (
		created_on		=>	q`'NOW'`,
		updated_on		=>	q`'NOW'`,
		serialkey			=>	undef,
		max_uses			=>	1,
		purchased_on	=>	undef,
		expires_on		=>	undef,
		software_id		=>	undef,
);
sub software {
	if ( @_ > 1 ) {
		my $Software = openprint::Software->find_one('name lc'=> lc openprint::Software->transform('name',$_[1]) );
		if ( ! $Software ) {
			$Software = new openprint::Software();
			$Software->save({name=>$_[1]});
		} # end if
		$_[0]{software_id} = $Software->id();
		$_[0]{software} = $Software->name();
	}
	if ( ! $_[0]{software} ) {
		$_[0]{software} = new openprint::Software( $_[0]{software_id} )->name();
	} # end if
	return $_[0]{software};
} # end sub software

sub Hosts {
	return map { $_->Host() } openprint::License_Host->find(license_id=>$_[0]{id});
} # end sub Hosts

sub delete {
  return $_[0]->destroy();
}

sub destroy {
  my $self = shift;
  my $result = '';
  foreach ( openprint::License_Host->find(license_id=>$$self{id})) {
    $result .= $_->destroy();
  }
  $result = $self->SUPER::destroy();
  return $result;
}

sub features {
  my $self = shift;
  if (@_) {
    $$self{features} = shift;
    $$self{features_json} = JSON::encode_json($$self{features});
  } elsif (!$$self{features}) {
    $$self{features} = $$self{features_json} ? JSON::decode_json($$self{features_json}) : {};
  }
  return $$self{features};
}

sub generate_key {
  my $self = shift;
  #my $private_key = $config{'Licensing Private Key'};
  #my $private_key = misc::load_file($openprint::log, '/var/www/crm/etc/ssl/cloudmule.key');
  my $private_key_str = misc::load_file($openprint::log, '/etc/ssl/cloudmule.key');
  my $public_key_str = misc::load_file($openprint::log, '/etc/ssl/cloudmule.pub');
  #$openprint::log->debug("Private key $private_key_str");

  my ($public_key, $private_key);
  #my $rsa = Crypt::RSA->new();
  if (!$private_key_str) {
    my $rsa = Crypt::OpenSSL::RSA->generate_key(1024);
    $openprint::log->debug($rsa->get_private_key_string());
    File::Slurp::write_file('/tmp/key', { atomic => 1, err_mode=>'carp' }, $rsa->get_private_key_string()) or warn "Couldn't save key file";
    File::Slurp::write_file('/tmp/key.pub', { atomic => 1, err_mode=>'carp' }, $rsa->get_public_key_string()) or warn "Couldn't save key file";

    #($public_key, $private_key) = $rsa->keygen();
    #$openprint::log->error("No private key, generating a new one");
    #$private_key->write(Filename => '/tmp/key');
    #$public_key->write(Filename => '/tmp/key.pub');
  } else {
    #$public_key = $rsa->import_key(\$public_key_str);
    #$private_key = $rsa->import_key(\$private_key_str);
  }

  my $rsa_public = Crypt::OpenSSL::RSA->new_public_key($public_key_str);
  my $rsa_private = Crypt::OpenSSL::RSA->new_private_key($private_key_str);
  $rsa_private->use_pkcs1_padding();
  $$self{serialkey} = encode_base64($rsa_private->private_encrypt($self->id().','.$self->features_json()));
  #$$self{serialkey} = encode_base64($rsa->encrypt($self->id().','.$self->features_json(), $private_key));
  my $hash = sha256_hex($$self{serialkey});
  #my $signature = $rsa_public->sign($$self{serialkey});
  #my $signature_hex = unpack("H*", $signature);
  #$openprint::log->debug("Hash $hash Signature $signature $signature_hex");
  $openprint::log->debug("Hash $hash");
  # Extract the first 8 characters of the hash as the license key
  my $short_license_key = substr($hash, 0, 16);
  my @codons = $short_license_key =~ /.{4}/g;
  $$self{hash} = join('-', @codons);

  #my $signature = $rsa->sign_message($hash, $private_key);
  #$openprint::log->debug("Hash $hash Signature $signature");
}

sub is_valid {
  #my $rsa = Crypt::RSA->new();
  # Verify the signature
  #my $is_valid = $rsa->verify_message($hash, $signature, $public_key);

}

1;
__END__
