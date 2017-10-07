package PQS::API::Materials;

use PQS::model::materials;
use JSON::XS qw(encode_json);

sub material_type_by_id {
  my ($self, $id) = @_;
  $self->header(-type => "application/json");
  return encode_json(PQS::model::materials::material_type_by_id($id));
}

sub material_type_by_name {
  my ($self, $name) = @_;
  $self->header(-type => "application/json");
  return encode_json(PQS::model::materials::material_type_by_name($name));
}

sub material_by_id {
  my ($self, $id) = @_;
  $self->header(-type => "application/json");
  return encode_json(PQS::model::materials::material_by_id($id));
}

sub material_by_strid {
  my ($self, $id) = @_;
  $self->header(-type => "application/json");
  return encode_json(PQS::model::materials::material_by_strid($id));
}

1;