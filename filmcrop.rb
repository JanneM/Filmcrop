#!/usr/bin/ruby
require 'RMagick'
require 'optparse'
require 'pp'

$diff_fac=0.1	# fraction frame width to search for an edge
$margin=1.0/8	# ignored top and bottom area
$ds=nil		# scale factor for the small images we work with
# Get a list of input files, optionally an output prefix (defaulting to
# "crop").

fheader="crop"
images=6

dofit=true
fitsize=0
doaverage=true
# create the intensity array corresponding to a given strip
# $margin is how much to ignore toward the edges

def make_intense(fstrip)

    rows=fstrip.rows
    cols =fstrip.columns

    acc = Array.new(cols)
    maxp = 0
    minp = 1000000

    cols.times {|x|
	pixels = fstrip.get_pixels(x,(rows*$margin),1,(rows-rows*$margin))
	mp=0.0
	pixels.each { |p|
	    val=p.intensity()
	    mp=val if mp < val
	}
	maxp = mp if mp > maxp
	minp = mp if mp < minp

	acc[x] = mp*1.0
    }
    acc.map! {|v| ((v)/(maxp))}
end

# Find the minima in the neighbourhood around each possible separation point

def find_minima(arr, frames)
    pstep = arr.length/frames
    diffstep = Integer(pstep*$diff_fac)

    mins=Array.new(frames+1)
    mins[0]=0
    mins[frames]=arr.length-1

    (frames-1).times {|sep|
	pc = (sep+1)*pstep
	min=100000
	finp=-1
	((pc-diffstep)..(pc+diffstep)).each {|p|
	    if arr[p]<min
		min=arr[p]
		finp=p
	    end 
	}
	mins[sep+1] = finp
    }
    mins
end

# find least square minima
def find_sqr_minima(strip, frames, avgframe)
    arr = strip.intensity
    print "frames: ", frames, "\n"
    pstep = arr.length/(frames)
    diffstep = Integer(pstep*$diff_fac)

    mins=Array.new(frames)

    (1..frames-2).each {|fr|

	    ps = Integer(fr*pstep)
	    pe = Integer(ps+avgframe)

	    # normalize
	    arr_start=arr.slice(ps-diffstep..ps+diffstep)
	    arr_end=arr.slice(pe-diffstep..pe+diffstep)
	    ms=arr_start.min
	    me=arr_end.min
	    arr_start.map! {|x| x-ms}
	    arr_end.map! {|x| x-me}

	    min=100000
	    finp=-1
	    (-diffstep..diffstep).each {|p|
		
		v=(arr_start[p+diffstep]**2 + 
		   arr_end[p+diffstep]**2)
		if v<min
		    min=v
		    finp=p
		end 
	    }

	    mins[fr]=[(ps+finp)*$ds, (pe+finp)*$ds]
    }
    mins[0]=[(mins[1][0]-avgframe*$ds), (mins[1][0])]
    mins[frames-1]=[mins[frames-2][1], mins[frames-2][1]+avgframe*$ds]
    mins
end


optparse = OptionParser.new { |opts|

    opts.banner="Usage: filmcrop [options] file1 file2 .."
    opts.on( '-i', '--images N', Integer, 'Number of images on a strip (default 6)' ) do |f|
	images=f
	if images<2
	    puts "Need at least two images per strip\n\n", opts
	    exit
	end
    end
    opts.on( '-f', "--[no-]fit=[SIZE]", Integer, "Fit the average frame size or given frame [SIZE] to every image (default)") do |f|
	if f==nil
	    dofit = true    # default
	    doaverage=true
	elsif f==false
	    dofit = false
	else
	    dofit = true
	    doaverage=false
	    fitsize=f
	end

    end
    opts.on( '-o', '--output FILE', 'Set output file name prefix (default "crop")' ) do |f|
	fheader=f
    end

    opts.on_tail( '-h', '--help', 'Get help' ) do
	puts opts
	exit
    end
}
begin optparse.parse!
rescue OptionParser::ParseError => e
    puts e, "\n", optparse
    exit 1
end

seps = images-1
files = ARGV

if files.length < 1
    print "Need at least one input file.\n"
    puts optparse
    exit(0)
end
#fheader=File.basename(infile, File.extname(infile))

Img = Struct.new(:fname,	# Full size file name
		 :intensity,	# average value array
		 :cuts,		# found cut positions
		 :fcut,		# final frame cuts
		 :row, :col)	# size of the scaled-down image 
strips=Array.new()
files.each {|infile|

    print "Processing file: ", infile, "\n"
    instrip = Magick::Image.read(infile).first
    instrip.rotate!(-90, '<')
    $ds=$ds||instrip.rows/200.0
    strip=instrip.resize(1/$ds)
    instrip.destroy!

    arr=make_intense(strip)
    cuts=find_minima(arr, images)
    
    a=Array.new()
    strips.push(Img.new(infile, arr, cuts,a, strip.rows, strip.columns))
    strip.destroy!
}

#strips.each {|s|
#    pp s.cuts
#}
#exit()

# fit to an average or given frame width 
if dofit
    print "fitting... \n"
    avg=0
    if doaverage		    # find average frame size
	total=0
	nr=0
	strips.each {|s|
	    (1..(images-2)).each {|i|	    # note '1'
		total+=(s.cuts[i+1]-s.cuts[i])
		nr+=1
	    }
	}
	#    print "Average: ", total,"/", nr, " = ", total/nr, "\n"
	avg = Integer(total/nr)
    else			    # use user-supplied size
	avg=fitsize/$ds
    end

    strips.each {|s|
	s.fcut=find_sqr_minima(s, images, avg)
    }

# No fixed frame, so just set the cuts to each local minimum
else			
    strips.each {|s|
	(0..(images-1)).each {|i|
	    f=[s.cuts[i]*$ds, s.cuts[i+1]*$ds]
	    s.fcut.push(f)
	}
    }
end

filenr=1
strips.each {|s|
    
    print "crop file: ", s.fname, "\n"
    instrip = Magick::Image.read(s.fname).first
    instrip.rotate!(-90, '<')

    (0..(images-1)).each {|i|
	cuts=s.fcut[i]

	outimg=instrip.crop(cuts[0],0,(cuts[1]-cuts[0]),instrip.rows,true)
	fname=format("%s.%03d.tif", fheader, filenr)
	filenr+=1
	outimg.write(fname)
	print "\t f# ", i, "\n"
	outimg.destroy!
    }
    instrip.destroy!
}

	
