/**
 * Autogenerated by Thrift
 *
 * DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
 */
using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using System.IO;
using Thrift;
using Thrift.Collections;
using Thrift.Protocol;
using Thrift.Transport;

[Serializable]
public class Ping : TBase
{
  private string action_id;

  public string Action_id
  {
    get
    {
      return action_id;
    }
    set
    {
      __isset.action_id = true;
      action_id = value;
    }
  }


  public Isset __isset;
  [Serializable]
  public struct Isset {
    public bool action_id;
  }

  public Ping() {
  }

  public void Read (TProtocol iprot)
  {
    TField field;
    iprot.ReadStructBegin();
    while (true)
    {
      field = iprot.ReadFieldBegin();
      if (field.Type == TType.Stop) { 
        break;
      }
      switch (field.ID)
      {
        case 1:
          if (field.Type == TType.String) {
            this.action_id = iprot.ReadString();
            this.__isset.action_id = true;
          } else { 
            TProtocolUtil.Skip(iprot, field.Type);
          }
          break;
        default: 
          TProtocolUtil.Skip(iprot, field.Type);
          break;
      }
      iprot.ReadFieldEnd();
    }
    iprot.ReadStructEnd();
  }

  public void Write(TProtocol oprot) {
    TStruct struc = new TStruct("Ping");
    oprot.WriteStructBegin(struc);
    TField field = new TField();
    if (this.action_id != null && __isset.action_id) {
      field.Name = "action_id";
      field.Type = TType.String;
      field.ID = 1;
      oprot.WriteFieldBegin(field);
      oprot.WriteString(this.action_id);
      oprot.WriteFieldEnd();
    }
    oprot.WriteFieldStop();
    oprot.WriteStructEnd();
  }

  public override string ToString() {
    StringBuilder sb = new StringBuilder("Ping(");
    sb.Append("action_id: ");
    sb.Append(this.action_id);
    sb.Append(")");
    return sb.ToString();
  }

}

