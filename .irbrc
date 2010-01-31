require 'irb/completion'
require 'irb/ext/save-history'
require 'set'




begin
  IRB.conf[:AUTO_INDENT]  = true # automatically indents blocks when input spans lines
  IRB.conf[:VERBOSE]      = true # adds some amount of detail to certain output
  IRB.conf[:SAVE_HISTORY] = 2000 # lines of history to save
rescue
  # load as module by doing `ln -s ~/.irbrc ~/irbrc.rb` and then in your programs, include `require '~/irbrc'`
  puts 'irbrc loaded as module'
end




# saves call stack and allows us to find callers for a method
$my_stack = []
set_trace_func proc { |event, file, line, id, binding, classname|
  if event == "call" #|| event == "c-call"
    $my_stack.push [classname, id]
  end
  if event == "return" #|| event == "c-return"
    $my_stack.pop
  end
}
def whoCalled()
  $my_stack[-3] # -1 is this method, -2 is the caller who wants to know, -3 is the one who called our caller
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




# shortcut for rubydocs
def ri(*names)
  system(%{ri #{names.map {|name| name.to_s}.join(" ")}})
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
  # naive way of finding key and value types for a hash
  def mapType(map=self)
    k = map.keys[0]
    return k.class.to_s+" --> "+map[k].class.to_s
  end

  def to_s
    hashPrint(self)
  end
  def inspect
    hashPrint(self)
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
  #   public class/instance members/methods (private_instance_methods, protected_instance_methods, public_instance_methods, singleton_methods, constants - superclass.constants)

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
end




class String
  def startsWith(prefix, test=self)
    if prefix.kind_of?(Array)
      prefix.any?{|p| startsWith(p, test)}
    elsif test.kind_of?(Array)
      test.any?{|t| startsWith(prefix, t)}
    else
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
#  puts a
#  puts b
#  puts x
#  puts y
#=>
#  1
#  2
#  3
#  4
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
