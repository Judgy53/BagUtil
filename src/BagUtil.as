import xeio.Utils;
import com.GameInterface.DistributedValue;
import com.GameInterface.InventoryItem;
import com.GameInterface.Game.Character;
import com.GameInterface.ShopInterface;
import com.Utils.LDBFormat;
import flash.geom.Point;
import mx.utils.Delegate;
import com.Utils.Text;
import com.Utils.Archive;

import com.GameInterface.Game.CharacterBase;
import com.GameInterface.Inventory;


class BagUtil
{    
	private var m_swfRoot: MovieClip;
	
	private var m_openButton: MovieClip
	private var m_sellButton: MovieClip
	
	private var m_Inventory:Inventory;
	private var m_OpenShop:ShopInterface;
	private var m_openBagsCommand:DistributedValue;
	private var m_sellItemsCommand:DistributedValue;
	private var m_OpenBagsValue:String;
	private var m_itemSellCount:Number = 0;
	private var m_itemsToSell:Array = [];
	private var m_itemsToOpen:Array = [];
	private var m_storedSignalListeners:Array;
	private var m_storedTokenTotals:Array;
	
	static var TALISMAN_BAGS:Array = [LDBFormat.LDBGetText(50200, 9264943)];
	static var WEAPON_BAGS:Array = [LDBFormat.LDBGetText(50200, 9289681)];
	static var GLYPH_BAGS:Array = [LDBFormat.LDBGetText(50200, 7719874), LDBFormat.LDBGetText(50200, 9284361)];
	
	public static function main(swfRoot:MovieClip):Void 
	{
		var bagUtil = new BagUtil(swfRoot);
		
		swfRoot.onLoad = function() { bagUtil.OnLoad(); };
		swfRoot.OnUnload =  function() { bagUtil.OnUnload(); };
		swfRoot.OnModuleActivated = function(config:Archive) { bagUtil.Activate(config); };
		swfRoot.OnModuleDeactivated = function() { return bagUtil.Deactivate(); };
	}
	
    public function BagUtil(swfRoot: MovieClip) 
    {
		m_swfRoot = swfRoot;
    }
	
	public function OnLoad()
	{
		var clientCharacterInstanceID:Number = CharacterBase.GetClientCharID().GetInstance();
        
        m_Inventory = new Inventory(new com.Utils.ID32(_global.Enums.InvType.e_Type_GC_BackpackContainer, clientCharacterInstanceID));
				
		m_openBagsCommand = DistributedValue.Create("BagUtil_OpenBags");
		m_openBagsCommand.SetValue(undefined);
		m_openBagsCommand.SignalChanged.Connect(OpenBagsCommand, this);
		
		m_sellItemsCommand = DistributedValue.Create("BagUtil_SellItems");
		m_sellItemsCommand.SetValue(undefined);
		m_sellItemsCommand.SignalChanged.Connect(SellItemsCommand, this);
		
		ShopInterface.SignalOpenShop.Connect(OnOpenShop, this);
		
		//Delay adding the buttons slightly, in case we load before the inventory
		setTimeout(Delegate.create(this, AddInventoryButtons), 1000);
	}
	
	public function OnUnload()
	{
		m_openButton.removeMovieClip(); 
		m_openButton = undefined;
		m_sellButton.removeMovieClip();
		m_sellButton = undefined;
		
		ShopInterface.SignalOpenShop.Disconnect(OnOpenShop, this);
		if (m_OpenShop != undefined)
		{
			m_OpenShop.SignalCloseShop.Disconnect(OnCloseShop, this);
		}
		
		m_openBagsCommand.SignalChanged.Disconnect(OpenBagsCommand, this);
		m_sellItemsCommand.SignalChanged.Disconnect(SellItemsCommand, this);
	}
	
	public function Activate(config: Archive)
	{
	}
	
	public function Deactivate(): Archive
	{
		var archive: Archive = new Archive();			
		return archive;
	}
	
	private function AddInventoryButtons()
	{
		var x = _root.backpack2.InvBackground0.m_BottomBar;
		
		m_openButton = x.attachMovie("ChromeButtonDark", "m_openButton", x.getNextHighestDepth(), {_x:x.m_TokenButton._x - 55, _y:x.m_TokenButton._y});
		m_openButton.disableFocus = true;
		m_openButton.textField.text = "Open";
		m_openButton.onMousePress = Delegate.create(this, function() { this.m_openBagsCommand.SetValue("all"); } );
		m_openButton._width = 50;
		
		m_sellButton = x.attachMovie("ChromeButtonDark", "m_sellButton", x.getNextHighestDepth(), {_x:x.m_TokenButton._x - 110, _y:x.m_TokenButton._y});
		m_sellButton.disableFocus = true;
		m_sellButton.textField.text = "Sell";
		m_sellButton.onMousePress = Delegate.create(this, function() { this.m_sellItemsCommand.SetValue(true); } );
		m_sellButton._width = 50;
		m_sellButton._visible = false;
	}
	
	private function ItemIsSafeToSell(item:InventoryItem):Boolean
	{
		if (item.m_Pips != 1 && item.m_Pips != 2) return false; //Only include 1 or 2 pip items
		if (item.m_Rarity != 2) return false; //Non-commons
		if (item.m_Rank != 1) return false; //Only include items at rank 1 (unranked)
		if (item.m_XP != 0) return false; //XP (mostly redundant with rank for commons)
		if (item.m_IsBoundToPlayer) return false; //Bound items
		return true;
	}
	
	private function ItemIsExtraordinary(item:InventoryItem)
	{
		//ColorLine = 43 Extraordinary items (red background?)
		return item.m_ColorLine == 43;
	}
		
	function OnOpenShop(shopInterface:ShopInterface)
	{
		m_OpenShop = shopInterface;
		m_OpenShop.SignalCloseShop.Connect(OnCloseShop, this);
		m_sellButton._visible = true;
	}

	function OnCloseShop()
	{
		m_OpenShop = undefined;
		m_sellButton._visible = false;
	}
	
	function SellItemsCommand()
	{
		var value = m_sellItemsCommand.GetValue();
		if (value != undefined)
		{
			m_sellItemsCommand.SetValue(undefined);
			BuildSellList();
			
			//It's slow to have all the currency listeners trigger while selling, so just... stop them... for now.
			var character:Character = Character.GetCharacter(CharacterBase.GetClientCharID());
			m_storedSignalListeners = character.SignalTokenAmountChanged["m_EventList"];
			character.SignalTokenAmountChanged["m_EventList"] = new Array();
			m_storedTokenTotals = new Array();
			character.SignalTokenAmountChanged.Connect(SlotTokenChanged, this);
			
			setTimeout(Delegate.create(this, SellItems), 500);
		}
	}
	
	private function SlotTokenChanged(tokenID:Number, newAmount:Number, oldAmount:Number)
	{
		//Store any currency events to fire at the end of the sell action
		if (!m_storedTokenTotals[tokenID])
		{
			m_storedTokenTotals[tokenID] = new Object();
			m_storedTokenTotals[tokenID].oldAmount = oldAmount;
		}
		m_storedTokenTotals[tokenID].newAmount = newAmount;
	}
	
	function BuildSellList()
	{
		var defaultBag/*:ItemIconBox*/ = _root.backpack2.m_IconBoxes[0];
		for (var i:Number = 0; i < defaultBag.GetNumRows(); i++)
		for (var j:Number = 0; j < defaultBag.GetNumColumns(); j++)
		{
			var item:InventoryItem = defaultBag.GetItemAtGridPosition(new Point(j, i)).GetData();
			
			if (item != undefined && ItemIsSafeToSell(item, false))
			{
				if (ItemIsExtraordinary(item))
				{
					//Extraordinaries go to the end of the list rather than the start so they sell last
					m_itemsToSell.push(item);
				}
				else
				{
					m_itemsToSell.unshift(item);
				}
			}
		}
		m_itemSellCount = m_itemsToSell.length;
	}
	
	function SellItems()
	{
		var item:InventoryItem = InventoryItem(m_itemsToSell.shift());
		if (item && m_OpenShop)
		{
			m_OpenShop.SellItem(m_Inventory.GetInventoryID(), item.m_InventoryPos);
			setTimeout(Delegate.create(this, SellItems), 50);
		}
		else
		{
			//Restore the token change signals, and emit the "final" change values
			var character:Character = Character.GetCharacter(CharacterBase.GetClientCharID());
			character.SignalTokenAmountChanged["m_EventList"] = m_storedSignalListeners;
			for (var tokenType in m_storedTokenTotals)
			{
				character.SignalTokenAmountChanged.Emit(tokenType, m_storedTokenTotals[tokenType].newAmount, m_storedTokenTotals[tokenType].oldAmount);
			}
			
			var sellTotal = (m_storedTokenTotals[_global.Enums.Token.e_Cash].newAmount - m_storedTokenTotals[_global.Enums.Token.e_Cash].oldAmount) || 0;
			com.GameInterface.Chat.SignalShowFIFOMessage.Emit("Sold " + m_itemSellCount + " item(s) for " + Text.AddThousandsSeparator(sellTotal) + " " + LDBFormat.LDBGetText("Tokens", "Token" + _global.Enums.Token.e_Cash) + ".", 0);
			
			if (m_itemSellCount > 0)
			{
				com.GameInterface.Game.Character.GetClientCharacter().AddEffectPackage("sound_fxpackage_GUI_trade_success.xml");
			}
		}
	}
	
	function OpenBagsCommand()
	{
		var value:String = m_openBagsCommand.GetValue();
		if (value != undefined)
		{
			m_OpenBagsValue = value.toLowerCase();
			m_openBagsCommand.SetValue(undefined);
			OpenBags();
		}
	}
	private function ShouldOpenItem(item:InventoryItem):Boolean
	{
		if ((m_OpenBagsValue == "all" || m_OpenBagsValue == "weapon") && Utils.Contains(WEAPON_BAGS, item.m_Name))
		{
			return true;
		}
		if ((m_OpenBagsValue == "all" || m_OpenBagsValue == "talisman") && Utils.Contains(TALISMAN_BAGS, item.m_Name))
		{
			return true;
		}
		if ((m_OpenBagsValue == "all" || m_OpenBagsValue == "glyph") && Utils.Contains(GLYPH_BAGS, item.m_Name))
		{
			return true;
		}
		return false;
	}
	
	function OpenBags()
	{
		if (m_Inventory.GetFirstFreeItemSlot() == -1)
		{
			com.GameInterface.Chat.SignalShowFIFOMessage.Emit("Inventory full, stopping.", 0);
			return;
		}
		
		var continueOpening:Boolean = false;
		var defaultBag/*:ItemIconBox*/ = _root.backpack2.m_IconBoxes[0];
		for (var i:Number = 0; i < defaultBag.GetNumRows(); i++)
		for (var j:Number = 0; j < defaultBag.GetNumColumns(); j++)
		{
			var itemSlot = defaultBag.GetItemAtGridPosition(new Point(j, i));
			var item:InventoryItem = itemSlot.GetData();
			
			if (item != undefined && ShouldOpenItem(item))
			{
				if (!itemSlot.GetSlotMC().item.m_HasCooldown)
				{
					m_Inventory.UseItem(item.m_InventoryPos);
					setTimeout(Delegate.create(this, OpenBags), 200);
					return;
				}
				continueOpening = true;
			}
		}
		
		if (continueOpening)
		{
			setTimeout(Delegate.create(this, OpenBags), 200);
		}
		else
		{
			com.GameInterface.Chat.SignalShowFIFOMessage.Emit("Open Complete.", 0);
		}
	}
}