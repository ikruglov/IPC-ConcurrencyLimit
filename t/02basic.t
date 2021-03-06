use strict;
use warnings;
use File::Temp;
use Test::More tests => 43;
use IPC::ConcurrencyLimit;

# TMPDIR will hopefully put it in the logical equivalent of
# a /tmp. That is important because no sane admin will mount /tmp
# via NFS and we don't want to fail tests just because we're being
# built/tested on an NFS share.
my $tmpdir = File::Temp::tempdir( CLEANUP => 1, TMPDIR => 1 );

SCOPE: {
  my $limit = IPC::ConcurrencyLimit->new(path => $tmpdir);
  isa_ok($limit, 'IPC::ConcurrencyLimit');

  ok(!$limit->release_lock(), 'No lock to release yet');

  my $id = $limit->get_lock;
  is($id, 1, 'First and only lock has id 1');

  $id = $limit->get_lock;
  is($id, 1, 'Repeated call to lock returns same id');

  ok($limit->is_locked, 'We have a lock');
  ok($limit->lock_id, 'Lock id still 1');

  ok($limit->release_lock(), 'Lock released');
  ok(!$limit->is_locked, 'We do not have a lock');
  is($limit->lock_id, undef, 'No lock');
  
  $id = $limit->get_lock;
  is($id, 1, 'New lock returns same id');

  my $limit2 = IPC::ConcurrencyLimit->new(path => $tmpdir);
  my $id2 = $limit2->get_lock();
  is($id2, undef, 'Cannot get second lock');

  is($limit->release_lock(), 1, 'Lock released');
  $id2 = $limit2->get_lock();
  is($id2, 1, 'Got other lock after first was released');
}

SCOPE: {
  my $limit = IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => 2);
  isa_ok($limit, 'IPC::ConcurrencyLimit');

  my $id = $limit->get_lock;
  ok($id, 'Got lock');

  my $idr = $limit->get_lock;
  is($idr, $id, 'Repeated call to lock returns same id');

  my $id2;
  INNER: {
    my $limit2 = IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => 2);
    $id2 = $limit2->get_lock();
    ok($id2, 'Got second lock');

    ok($id != $id2, 'Lock ids are not equal');

    my $limit3 = IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => 2);
    my $id3 = $limit3->get_lock();
    is($id3, undef, 'Only two locks to go around');
  } # end INNER

  my $limit4 = IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => 2);
  my $id4 = $limit4->get_lock();
  is($id4, $id2, 'Lock 2 went out of scope, got new lock with same id');

  my $limit5 = IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => 2);
  my $id5 = $limit5->get_lock();
  is($id5, undef, 'Only two lock to go around');

  undef $limit;

  my $limit6 = IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => 2);
  my $id6 = $limit6->get_lock();
  is($id6, $id, 'Recycled first lock');
} # end SCOPE

SCOPE: {
  my $max = 20;
  my @limits = map {
    IPC::ConcurrencyLimit->new(path => $tmpdir, max_procs => $max)
  } (1..$max+1);

  foreach my $limitno (0..$#limits) {
    my $limit = $limits[$limitno];
    my $id = $limit->get_lock();
    if ($limitno == $#limits) {
      ok(!$id, 'One too many locks');
    }
    else {
      ok($id, 'Got lock');
    }
  }
}


