package PQS::API;
use base REST::Application;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use PQS::DB;
use CGI;
use PQS::API::Materials;
use PQS::API::Service;

sub setup {
  my $self = shift;
  $self->resourceHooks(
    '/model/materials/type/(\d+)' => \&PQS::API::Materials::material_type_by_id,
    '/model/materials/(\d+)' => \&PQS::API::Materials::material_by_id,
    '/model/materials/(\w+)' => \&PQS::API::Materials::material_by_strid,
    '/model/service/(\d+)/materials' => \&PQS::API::Service::materials,
    '/model/service/materials' => \&PQS::API::Service::materials,
  );
}

sub read {
  my $q = CGI->new;
  my $data = $q->param('POSTDATA');
  return $data;
}

1;