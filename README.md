thermoruby
==========

DIY thermostat project designed to let you operate multiple network controlled thermostats on heaters of various types.

Currently, supported hardware is a Raspberry Pi with particular electronics and driver support. More details on these coming soon.

There are several parts of this project:

* A ruby client = thermoruby.rb and related controller and test files
* A node.js server = this is used for testing and can be used for operations. It does very little - simply returning configurations files when requested

More documentation to come, and contact welcome from interested users or contributors. science@misuse.org

(c) 2013 Steve Midgley 

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use the files in this project except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

Author's statement on warranties, conditions, guarantees or fitness of software for any purpose

No warranty is expressed or implied, per Apache license. If you use this software it is vital that you understand this.
This software could be used to control expensive heating equipment. There is no guarantee that it will function properly
for your heater, even if the tests are working and you install it correctly. It could damage your heating equipment.
It could cause the heating equipment to malfunction. It could cause damage to property, create fires, gas leaks or electrical malfunctions.
It could harm or kill humans or animals. It could do other, unknown harmful things.
I nor any contributor has any liability for what you do with this software or from the effects of operating this software.
You cannot use this software without agreeing to the Apache license which prevents you from seeking damages or other recourse
for any function or lack of function related to this software, as described above or otherwise.
