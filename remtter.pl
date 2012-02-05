#!/usr/bin/env perl

use strict;
use warnings;

use Net::Twitter::Lite;
use Data::Dumper;
use YAML::Syck;
use Encode;
use Net::IRC;

my $conf = $ARGV[0] || 'config.yaml';
my $cache = '/path/to/twitter/information/cache/directory/';

print "+Loading YAML:$conf\n";
my $yaml = YAML::Syck::LoadFile($conf);

my (%new_list,%new_follower);
my (%old_list,%old_follower);

#load data
&get_current_data;
&load_old_data;

my @msg;

#get diff
foreach my $id(keys %old_follower){
	if(defined $new_follower{$id}){
		if($old_follower{$id} ne $new_follower{$id}){
			push(@msg,"= $old_follower{$id} is now known as $new_follower{$id}");
		}
	}else{
		push(@msg,"- $old_follower{$id} removed.");
	}
}

foreach my $id(keys %new_follower){
	unless(defined $old_follower{$id}){
		push(@msg,"+ $new_follower{$id} folloed.");
	}
}

foreach my $id(keys %old_list){
	if(defined $new_list{$id}){
		if($old_list{$id} ne $new_list{$id}){
			push(@msg,"= $old_list{$id} is renamed to $new_list{$id}");
		}
	}else{
		push(@msg,"- $old_list{$id} removed");
	}
}

foreach my $id(keys %new_list){
	unless(defined $old_list{$id}){
		push(@msg,"+ $new_list{$id} added");
	}
}

#save data
&save_current_data;

exit unless scalar @msg;

#notice to IRC
my $irc = Net::IRC->new;
my %irc_conf = (
	Nick => $yaml->{irc}{nick},
	Username => $yaml->{irc}{name},
	Server => $yaml->{irc}{server},
	Port => $yaml->{irc}{port},
	Ircname=> $yaml->{irc}{desc},
);
$irc_conf{Password} = $yaml->{irc}{password} if defined $yaml->{irc}{password};
my $ch = $yaml->{irc}{channel};
my $c   = $irc->newconn(%irc_conf);
$c->add_handler('endofmotd',\&on_connect);
$irc->start;
exit;

sub on_connect
{
	my($self,$event) = @_;
	$self->join($ch);

	foreach my $line(@msg){
		$self->privmsg($ch,$line);
	}
	$self->quit;
}

sub get_current_data
{
	my $nt = Net::Twitter::Lite->new(%{$yaml->{account}});
	$nt->access_token($yaml->{account}{token});
	$nt->access_token_secret($yaml->{account}{secret});

	unless ( $nt->authorized ) {
		print "Cannot Authorized.\n";
		exit;
	}

	my $cursor = '-1';
	print "+Get Current Followers\n";
	while($cursor ne '0'){
		my $entry = $nt->list_memberships({cursor => $cursor , user=>$yaml->{account}{name}});
		$cursor = $entry->{next_cursor};
		foreach my $item(@{$entry->{lists}}){
			$new_list{$item->{id_str}} = Encode::encode($yaml->{irc}{charset},$item->{full_name});
		}
	}

	$cursor = '-1';
	print "+Get Current Lists\n";
	while($cursor ne '0'){
		my $entry = $nt->followers({cursor => $cursor});
		$cursor = $entry->{next_cursor};
		foreach my $user(@{$entry->{users}}){
			$new_follower{$user->{id_str}} = $user->{screen_name};
		}
	}
}

sub load_old_data
{
	open(my $fh,$cache.$yaml->{account}{name}.'.followers') or return;
	foreach my $line(<$fh>){
		chomp $line;
		my($id,$name) = split(/:/,$line);
		$old_follower{$id} = $name;
	}
	close($fh);
	
	open($fh,$cache.$yaml->{account}{name}.'.lists') or return;
	foreach my $line(<$fh>){
		chomp $line;
		my($id,$name) = split(/:/,$line);
		$old_list{$id} = $name;
	}
	close($fh);
}

sub save_current_data
{
	open(my $fh,'>'.$cache.$yaml->{account}{name}.'.followers') or return;
	foreach my $id(keys %new_follower){
		print $fh "$id:$new_follower{$id}\n";
	}
	close($fh);
	
	open($fh,'>'.$cache.$yaml->{account}{name}.'.lists') or return;
	foreach my $id(keys %new_list){
		print $fh "$id:$new_list{$id}\n";
	}
	close($fh);
}
