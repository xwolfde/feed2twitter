#!/usr/bin/perl
#
# Feed2Twitter
# Skript, um Feeds zu einem Twitterkanal zu verbreiten
#
use warnings;
use strict;

use Net::Twitter::Lite;
use XML::Feed;
use File::Spec;
use Storable;
use Data::Dumper;
use Getopt::Long;
###############################################################################
my $CONFIG = {
        "api-key"               => 'your-api-key',
        "consumer_key"          => 'your-consumer-key',
        "consumer_secret"       => 'your-consumer-secret',

	"access_token_file"	=> 'access_token.dat',
	"feedindex_file"	=> 'feedindex.dat',
	"geo_lat"		=> '49.573678096',
	"geo_long"		=> '11.027634143',
	"cutstring"		=> 1,

};
	# Konstanten

my $WORKDATA;
	# Hash fuer Arbeitsdaten
my $tweet;
	# Globales Tweet-Objekt
my $feed;
	# Globales Feed-Objekt
my $DEBUG;
	# Debugmode?  Kann ueber Options gesetzt werden
###############################################################################

Init();
if ($WORKDATA->{'status'} eq 'newaccount') {
	registerNewAccount();
}
if ($WORKDATA->{'msg'}) {
	# Sende Nachricht	
	tweetMsg();
} else {
	tweetFeed();
}
exit;

###############################################################################
# Einlesen der Aufrufparameter oder Ausgabe der Optionen
sub Init {
	my $feedurl;
	my $twitteraccount;
	my $message;
	my $ismsg;
	my $hashtag;
	my $quiet;
# 	my %consumer_tokens = (
#    		consumer_key => $CONFIG->{'consumer_key'},
#   		consumer_secret => $CONFIG->{'consumer_secret'},
#		);
#	$tweet = Net::Twitter::Lite->new(%consumer_tokens);

	my $options = GetOptions("feed=s" => \$feedurl,
		"twitter=s" => \$twitteraccount,
		"msg" => \$ismsg,
		"debug" => \$DEBUG,
		"hashtag=s" => \$hashtag,
		"quiet"	=> \$quiet,
	);

	if (((not $feedurl) && (not $ismsg)) || (not $twitteraccount) ) {
		print STDERR "Syntax error. Please use: \n";
		print STDERR "$0 (--feed=FEEDURL|--msg) --twitter=TWITTERACCOUNT [--hashtag=tag] [--debug] [--quiet]\n";
		exit;
	}
	if ($quiet) {
		$WORKDATA->{'quiet'} = 1;
	}
	if ($ismsg) {
		print "Enter text to tweet (max 140 chars): ";
		$message = <STDIN>;
		chomp($message);
		$feedurl = "";
	}
	$WORKDATA->{'feedurl'} = $feedurl if ($feedurl);
	$WORKDATA->{'twitteraccount'} = $twitteraccount;
	$WORKDATA->{'msg'} = $message if ($message);
	$hashtag =~ s/[^a-z0-9]+//gi;
	$WORKDATA->{'hashtag'} = $hashtag if ($hashtag);


	my $liste;

	if (-r 	$CONFIG->{'access_token_file'}) {
		my $foundaccount =0;

		my $tokens = retrieve($CONFIG->{'access_token_file'});
		if ($tokens) {
			if (ref($tokens) =~ /ARRAY/i) {
				@$liste = @$tokens;
				if ($DEBUG) {
				print STDERR "access_token: $liste->[0]\n";
				print STDERR "access_token_secret: $liste->[1]\n";	
				print STDERR "pin: $liste->[2]\n";
				print STDERR "twitter: $liste->[3]\n";
				}
				if ($liste->[3] eq  $twitteraccount) {
					$foundaccount =1;
				        $WORKDATA->{'account'} = $liste->[3];
                                        $WORKDATA->{'access_token'} = $liste->[0];
                                        $WORKDATA->{'access_token_secret'} =$liste->[1];
                                        $WORKDATA->{'verifier'} = $liste->[2];
				}
					
			} else {
				my $key;
				foreach $key (keys %{$tokens}) {
					@$liste = @{$tokens->{$key}};
					if ($DEBUG) {
	                                print STDERR "access_token: $liste->[0]\n";
       	                         	print STDERR "access_token_secret: $liste->[1]\n";
                                	print STDERR "pin: $liste->[2]\n";
                                	print STDERR "twitter: $liste->[3]\n";
					}
					if ($liste->[3] eq  $twitteraccount) {
                                        	$foundaccount =1;
						$WORKDATA->{'account'} = $liste->[3];
						$WORKDATA->{'access_token'} = $liste->[0];
						$WORKDATA->{'access_token_secret'}= $liste->[1];
						$WORKDATA->{'verifier'} = $liste->[2];
                                	}
				}
			}
			if (not $foundaccount) {
				 $WORKDATA->{'status'} = 'newaccount';
			} else {
				$WORKDATA->{'status'} = 'update';
			}
		} else {
			 $WORKDATA->{'status'} = 'newaccount';
		}
	} else {
		$WORKDATA->{'status'} = 'newaccount';
	}

}
###############################################################################
sub registerNewAccount {
      my %consumer_tokens = (
                consumer_key => $CONFIG->{'consumer_key'},
                consumer_secret => $CONFIG->{'consumer_secret'},
                );
     $tweet = Net::Twitter::Lite->new(%consumer_tokens);

    my $auth_url = $tweet->get_authorization_url;
    print " Authorize this application at: $auth_url\nThen, enter the PIN# provided to continue: ";

    my $pin = <STDIN>; # wait for input
    chomp $pin;
	if ($pin) {

	    # request_access_token stores the tokens in $nt AND returns them
    		my @access_tokens = $tweet->request_access_token(verifier => $pin);

    		# save the access tokens
		my $tokens;
		if (-r  $CONFIG->{'access_token_file'}) {
			$tokens = retrieve($CONFIG->{'access_token_file'});
			if (ref($tokens) =~ /ARRAY/i ) {
				my $newto;
				$newto->{$tokens->[3]} = $tokens;
				$newto->{$CONFIG->{'twitteraccount'}} = \@access_tokens;
				$tokens = $newto;
				
			} else {
				$tokens->{$CONFIG->{'twitteraccount'}} = \@access_tokens;
			}	
		} else {
			$tokens->{$CONFIG->{'twitteraccount'}} = \@access_tokens;
		}
		 store $tokens, $CONFIG->{'access_token_file'};
	 	$WORKDATA->{'status'} = 'update';
	} else {
		print STDERR "No verifier given. Stopping script.\n";
		exit;
	}
}
###############################################################################
sub tweetMsg {
	if (not $WORKDATA->{'msg'}) {
		print STDERR "No message to tweet...?\n";
		exit;
	}
	if ((not $WORKDATA->{'access_token'}) || (not $WORKDATA->{'access_token_secret'})) {
		print STDERR "Access token/Access token secret not avaible\n";
		exit;
	}
        my %consumer_tokens = (
                consumer_key => $CONFIG->{'consumer_key'},
                consumer_secret => $CONFIG->{'consumer_secret'},
                );
        $tweet = Net::Twitter::Lite->new(%consumer_tokens);

	$tweet->access_token($WORKDATA->{'access_token'});
	$tweet->access_token_secret($WORKDATA->{'access_token_secret'});
	if ($WORKDATA->{'hashtag'}) {
		my $tag = $WORKDATA->{'hashtag'};
		if ($WORKDATA->{'msg'} =~ / $tag /i) {
			$WORKDATA->{'msg'} =~ s/ $tag / #$tag /i
		} else {
			$WORKDATA->{'msg'} .= " #".$tag;
		}
	}
	my $text = formatMsg($WORKDATA->{'msg'});
	if (not $text) {
		print STDERR "Message $WORKDATA->{'msg'} could not be formated\n";
		exit;
	}
	
	my $result = eval { $tweet->update({status => $text, lat=> $CONFIG->{'geo_lat'}, long=> $CONFIG->{'geo_long'} }) };
	if ($DEBUG) {
   	 print Dumper $result;
	}
	print "Tweet \n\t$text\n send to twitter\n";	
}
###############################################################################
sub formatMsg {
	my $string = shift;
	my $res;
	if ((length($string) > 140) && ($CONFIG->{'cutstring'})) {
		$res = substr($string,0,137);
		$res .= "...";
	} elsif ((length($string) > 140) && (not $CONFIG->{'cutstring'})) {
		print STDERR "Message too long. Maximal numbers is 140 chars. Your message had ".length($string);
		return;
	} else {
		$res = $string;	
	}
	return $res;
}
###############################################################################
sub tweetFeed {
	if (not $WORKDATA->{'feedurl'}) {
		print STDERR "No feedurl given?\n";
		exit;
	}
	$feed = XML::Feed->parse(URI->new($WORKDATA->{'feedurl'}))
		or die XML::Feed->errstr;
	$tweet->access_token($WORKDATA->{'access_token'});
        $tweet->access_token_secret($WORKDATA->{'access_token_secret'});
	my $pubindex = getTweetIndex();	

	print $feed->title, "\n" if ($DEBUG);
	my $titel;
	my $id;
	my $cat;
	my $link;
	my $tags;
	my $tagliste;
	my $guid;
	my $msg;
	my $lenlink;
	my $lenhashtag = 0;
	my $lentitel;
	my $maxtitellen;
	my $hashtagintitel = 0;

	if ($WORKDATA->{'hashtag'}) {
		$lenhashtag = length($WORKDATA->{'hashtag'})+2;
	} 
	for my $entry ($feed->entries) {
		$hashtagintitel = 0;

		$titel = $entry->title();
		$lentitel = length($titel);
		$guid = $entry->{'entry'}->{'guid'};
		if ($DEBUG) {
			print "$titel\n";
			print "\tguid: $guid\n";
		}

		$lenlink = length($guid);
		if (($titel =~ /^$WORKDATA->{'hashtag'}/i) || ($titel =~ / $WORKDATA->{'hashtag'}/i)) {
			$lenhashtag =0;
			$hashtagintitel = 1;
			$titel  =~ s/ ($WORKDATA->{'hashtag'})/ #$1/i;
			$titel  =~ s/^($WORKDATA->{'hashtag'})/#$1/i;	
		}
	        $maxtitellen = 137 - $lenhashtag - $lenlink;
		if ($lentitel > $maxtitellen) {
			$titel = substr($titel,0,$maxtitellen-3);
			$titel .= "...";
		}		
		$msg = $titel." - ".$guid;
		$msg .= " #".$WORKDATA->{'hashtag'} if (($WORKDATA->{'hashtag'}) && (not $hashtagintitel));
		
		 print "Message:  $msg\n" if (not $WORKDATA->{'quiet'});
		if ($pubindex->{$WORKDATA->{'twitteraccount'}}->{$WORKDATA->{'feedurl'}}->{$guid})  {
			print "\t..already tweeted at $pubindex->{$WORKDATA->{'twitteraccount'}}->{$WORKDATA->{'feedurl'}}->{$guid}->{'tweettime'}\n" if (not $WORKDATA->{'quiet'});

		} else {
			$pubindex->{$WORKDATA->{'twitteraccount'}}->{$WORKDATA->{'feedurl'}}->{$guid}->{'tweettime'} = localtime(time);
			$pubindex->{$WORKDATA->{'twitteraccount'}}->{$WORKDATA->{'feedurl'}}->{$guid}->{'msg'} = $msg;
			print "\t...send to Twitter\n" if (not $WORKDATA->{'quiet'});
			$tweet->update({status => $msg, lat=> $CONFIG->{'geo_lat'}, long=> $CONFIG->{'geo_long'} });
			sleep(1);	
		}
	}
	store($pubindex,$CONFIG->{'feedindex_file'});
               if ($DEBUG) {
                       print "new index:\n";
                       print Dumper $pubindex;
               }


}
###############################################################################
sub getTweetIndex {
	my $result;
	if (-r $CONFIG->{'feedindex_file'}) {
		$result = retrieve($CONFIG->{'feedindex_file'});
	}
	if ($DEBUG) {
		print Dumper $result;
	}
	return $result;

}
###############################################################################
# EOF
