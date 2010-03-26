# my.irbrc -- useful ruby methods for debugging and general use.
# Copyright (C)2010 Carnegie Mellon University
# Written by george.haff (@gmail)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.




require 'irb/completion'
require 'irb/ext/save-history'
require 'set'



asModule = false
begin
  IRB.conf[:AUTO_INDENT]  = true # automatically indents blocks when input spans lines
  IRB.conf[:VERBOSE]      = true # adds some amount of detail to certain output
  IRB.conf[:SAVE_HISTORY] = 2000 # lines of history to save
rescue
  # load as module by doing `ln -s ~/.irbrc ~/irbrc.rb`
  # and then in your programs, include `require '~/irbrc'`
  puts 'irbrc loaded as module'
  asModule = true
end




# shortcut for rubydocs
def ri(*names)
  system(%{ri #{names.map {|name| name.to_s}.join(" ")}})
end




# saves call stack and allows us to find callers for a method
$my_stack = []
set_trace_func proc { |event, file, line, id, binding, classname|
  if event == "call" #|| event == "c-call"
    $my_stack.push [classname, id]
  elsif event == "return" #|| event == "c-return"
    $my_stack.pop
  end
}
def whoCalled()
  # -1 is this method "whoCalled()",
  # -2 is the caller who wants to know,
  # -3 is the one who called our caller
  $my_stack[-3]
end
def disableWhoCalled()
  # beacause the trace_func seems to really slow down irb with deep stacks...
  set_trace_func nil
end
if asModule
  disableWhoCalled()
end




# for doing distributed work, with a limited number of concurrent jobs.
# 'job' blocks handed to this are responsible for their own locks
# and cleaning up any threads they spawn.
# also see Array.distribute() below
# how to use:
#   distributor(700) {|i| sleep(rand(0)) }
#TODO: wrap yield calls in rescue block?, expand to ThreadGroup array instead of thread array?
def distributor(totalJobs, maxThreads=100)
  toSpawn   = [totalJobs, maxThreads].min
  nextJobNo = 0
  threads   = []
  while nextJobNo < totalJobs
    ##puts "spawning up to #{toSpawn} new jobs"
    (nextJobNo..[nextJobNo+toSpawn, totalJobs].min-1).each {|t|
      threads << Thread.new() {
        ##puts "starting #{t}"
        yield(t)
        ##puts "finished #{t}"
      }
    }
    nextJobNo += toSpawn
    begin
      sleep(10**-6) # sleep the minimum (one ruby time quantum)
      threads = threads.select {|x| x.alive? }
      toSpawn = maxThreads - threads.size
    end until toSpawn > 0
  end
  ##puts "done, cleaning up"
  threads.each {|x| x.join }
end




# turns a collection of arrays of values into
# a hash from the collection of all values to a trivial hash (all keys present map to true) with the array indexes as keys
#   arraysToIndicatorHash([:a,:b,:c], [:b,:c,:d], [:a,:c,:d])
#   => { :a => { 0 => true,  2 => true },
#        :b => { 0 => true, 1 => true },
#        :c => { 0 => true, 1 => true, 2 => true },
#        :d => { 1 => true, 2 => true }
#      }
# TODO: turn trivial hashes into proper set objects
def arraysToIndicatorHash(*aa)
  h = {}
  aa.each_index{|i|
    a = aa[i]
    a.each{|x|
      if not h.has_key?(x)
        h[x] = {}
      end
      h[x][i] = true
    }
  }
  h
end




# prints a hash of hashes as a matrix.
# assumes fixed width font but makes no assumptions about width.
# assumes all items in the data (or whatever they become after a .to_s call) are free of newlines.
#   puts prettyPrintAttrs(arraysToIndicatorHash([:a,:b,:c], [:b,:c,:d], [:a,:c,:d]))
#=> index  0     2     1
#   =======================
#   a      true  true  -
#   b      true  -     true
#   c      true  true  true
#   d      -     true  true
def prettyPrintAttrs(attrs, headerKeys=nil, keyHeaderName="index", colSpacing=2, defaultBlank="-", rotate=false)
  if headerKeys.nil?
    ks = {}
    attrs.each_value {|v|
      v.keys.each {|k|
        ks[k] = (ks[k]||0)+1
      }
    }
    headerKeys = ks.keys.sort{|a,b| ks[b]<=>ks[a] } # puts sparse columns at the end
  end
  cols = [[keyHeaderName]]
  headerKeys.each{|k| cols<<[k.to_s] }
  attrs.each {|k, v|
    cols[0] << k.to_s
    headerKeys.each_index {|i|
      cols[i+1] << if v.has_key?(headerKeys[i])
        v[headerKeys[i]].to_s
      else
        defaultBlank
      end
    }
  }
  if rotate
    cols = cols.transpose
  end
  sizes = []
  cols.each {|col|
    sizes << col.max{|a,b| a.length<=>b.length }.length
  }
  ret = ""
  cols[0].each_index {|i|
    if i==1
      ret += "="*(sizes.inject{|sum,n| sum+n }+colSpacing*(sizes.length-1)) + "\n"
    end
    cols.each_index {|j|
      ret += cols[j][i].ljust(sizes[j]+colSpacing)
    }
    ret += "\n"
  }
  ret
end




# has problems if the keys of the hash are hashes themselves,
# or if a particular object's .to_s is ugly
# example usage: puts hashPrint({:a => {:b => :c, :d => :e}, :f => :g})
# todo: do s/\n/prefix\n/ on any .to_s calls?
def hashPrint(h, prefix="")
  spacer = "  "
  if h.class == Hash
    "{\n" + h.inject(""){ |o, (k, v)|
      o + prefix + spacer + k.inspect + " => " + hashPrint(v, prefix+spacer) #TODO: k.inspect WAS k.to_s
    } + prefix + "}\n"
  else #TODO: add handling of Array here?
    h.inspect + "\n" #TODO: h.inspect WAS h.to_s
  end
end

def hashPrintSorted(h, depth=0, sortFn=lambda{|x,y|lex(x,y)})
  if h.class == Hash
    "{\n" + h.keys.sort{|x,y|sortFn.call(x,y)}.inject(""){ |o, k|
      o + "  "*(depth+1) + k.to_s + " => " + hashPrintSorted(h[k], depth+1, sortFn)
    } + "  "*depth + "}\n"
  else
    h.to_s + "\n"
  end
end

class Hash
  def to_s
    hashPrint(self)
  end
  def inspect
    hashPrint(self)
  end

  # naive way of finding key and value types for a hash
  def self.mapType(map)
    k = map.keys[0]
    return k.class.to_s+" --> "+map[k].class.to_s
  end
  def mapType(map=self)
    Hash.mapType(map)
  end

  # redefines values of the hash, block provided should return new value to replace the 'v' it is given
  def remap
    self.merge(self){|k,v| yield v} #TODO???: yield k,v instead?
  end
  def remap!
    self.merge!(self){|k,v| yield v} #TODO???: yield k,v instead?
  end
end



class Integer
  # use like .times(), except that this will stop when the block returns true.
  # that is, it will execute the block at most the specified number of times
  # (in cases where the block continually returns falsey values or throws
  # exceptions), ultimately returning the value of the last iteration or
  # rethrowing the last exception -- or it stops and returns the result of
  # the first iteration that returns a truthy value.
  # ...really, its for doing retries.
  def tries
    iteration = 0
    success   = false
    while iteration < self and not success
      iteration += 1
      begin
        success = yield iteration
      rescue Exception => err
        if iteration == self
          raise err
        end
      end
    end
    return success
  end
end




module Enumerable
  # like Enumerable::select{}.size, but presumably doesnt use as much space
  def count
    self.inject(0){|total, o| total + (yield(o) ? 1 : 0)}
  end
end




class Object
  # add to these:
  #   whether a method takes a block?
  #   public||private class||instance members||methods
  #     ( private_instance_methods, protected_instance_methods, public_instance_methods,
  #     singleton_methods, constants - superclass.constants )

  # detailed object information
  def introspect(obj = self)
    klass      = obj.class
    heirarchy  = klass.name
    superklass = klass.superclass
    modules    = klass.ancestors.to_set.delete(klass)
    while not superklass.nil?
      modules.delete(superklass)
      heirarchy += " < " + superklass.name
      superklass = superklass.superclass
    end
    puts "type:\n  " + heirarchy + "\n"
    puts "including modules:\n  " + modules.to_a.join(", ") + "\n"
    methodExtractor = Regexp.new("#<Method: (#{klass.name}(.*?)?#)?(.*?)>")
    puts "having methods:\n" + obj.methods.map { |methodString|
      methodRef       = obj.method(methodString.intern)
      definedIn, name = methodExtractor.match(methodRef.inspect)[2, 3]
      if definedIn.nil? || definedIn.empty?
        definedIn = ""
      else
        definedIn += " "
      end
      "  " + definedIn + name + " :" + methodRef.arity.to_s
    }.sort.join("\n") + "\n"
    puts "inspection:\n  " + obj.inspect + "\n"
  end

  # detailed object information in hash format
  def introspectHash(obj = self)
    klass                = obj.class
    klassname            = klass.name
    info                 = {}
    modules              = klass.ancestors.to_set
    info[:inspect]       = obj.inspect
    info[:typeHeirarchy] = []
    info[:methods]       = {}

    while not klass.nil?
      info[:typeHeirarchy] << klass.name
      modules.delete(klass)
      klass = klass.superclass
    end
    info[:modules] = modules.to_a

    methodExtractor = Regexp.new("#<Method: (#{klassname}(\\((.*?)\\))?#)?(.*?)>")
    obj.methods.each { |methodString|
      methodRef       = obj.method(methodString.intern)
      definedIn, name = methodExtractor.match(methodRef.inspect)[3, 4]
      if definedIn.nil? || definedIn.empty?
        definedIn = klassname
      end
      info[:methods][name] = { :arity     => methodRef.arity,
                               :definedIn => definedIn }
    }

    return info
  end

end




# returns array with all combinations of incident arrays:
#   ["text/","application/"]**["x-yaml","yaml"]
#   => ["text/x-yaml", "text/yaml", "application/x-yaml", "application/yaml"]
class Array
  def **(a)
    self.inject([]) { |m, x|
      a.inject(m) { |n, y|
        n << x.to_s+y.to_s
      }
    }
  end

  # extends distributor() from above...
  # example use: doing some archiving job on a list of websites, with (up to) 3 active at a time
  #   ['www.google.com', 'www.cnn.com', 'www.cmu.edu', 'www.slashdot.org', 'bash.org'].distribute(3) {|site, arrayIndex|
  #     puts "polling site #{site}"
  #     mirrorAndSave(site)  #or... sleep(rand(7))
  #     puts "done with #{site}"
  #   }
  def distribute(maxThreads=100)
    distributor(self.size, maxThreads) {|i| yield(self[i], i) }
    self
  end
end




class String
  def startsWith(prefix)
    String.startsWith(prefix, self)
  end
  def self.startsWith(prefix, test)
    if prefix.kind_of?(Array)
      prefix.any?{|p| String.startsWith(p, test)}
    elsif test.kind_of?(Array)
      test.any?{|t| String.startsWith(prefix, t)}
    else
      #TODO: would a regex be better here?
      prefix.eql?(test[0, prefix.length])
    end
  end
end




def cmp(x, y)
  x <=> y
end

def lex(x, y)
  cmp(x.to_s, y.to_s)
end

def identity(i)
  i
end

#use thusly:
#  a,b = order(1,2)
#  x,y = order(4,3)
#  puts [a,b,x,y].inspect
#=> [1, 2, 3, 4]
def order(a, b)
  if b<a
    [b, a]
  else
    [a, b]
  end
end




# for backwards compatibility, .tap() is standard in ruby 1.9, but not before
if not defined? tap
  class Object
    def tap
      yield self
      self
    end
  end
end




# some of the methods here that are attached to classes have an
# optional argument that defaults to self.  this is from the first
# iteration of the methods that stood alone.
