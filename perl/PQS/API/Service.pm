package PQS::API::Service;

use PQS::API;
use PQS::model::service;
use JSON::XS qw(encode_json decode_json);

sub materials {
  my ($self, $sid) = @_;
  $self->header(-type => "application/json");

  if ($self->getRequestMethod() eq "POST") {
    my $data = PQS::API::read();
    $data = decode_json($data);
    PQS::model::service::set_material_estimate($data->{estimate}, $data->{id}, $data->{sid}, $data->{mid}, $data->{qty_index});
    PQS::model::service::set_material_actual($data->{actual}, $data->{id}, $data->{sid}, $data->{mid}, $data->{qty_index});
    return 200;
  }

  return encode_json(PQS::model::service::get_material_usage($sid));
}

1;